-- Supabase SQL Editor で一度だけ実行
create table if not exists public.bm_rooms (
 code text primary key, host_token text not null, phase text not null default 'lobby',
 round_no int not null default 0, total int not null default 10,
 questions jsonb not null default '[]'::jsonb, created_at timestamptz not null default now()
);
create table if not exists public.bm_players (
 id uuid primary key default gen_random_uuid(), room_code text not null references public.bm_rooms(code) on delete cascade,
 token text not null unique, name text not null, score int not null default 0, joined_at timestamptz not null default now()
);
create table if not exists public.bm_answers (
 room_code text not null references public.bm_rooms(code) on delete cascade,
 round_no int not null, player_id uuid not null references public.bm_players(id) on delete cascade,
 answer text not null, primary key(room_code,round_no,player_id)
);
create index if not exists bm_players_room on public.bm_players(room_code);
create index if not exists bm_answers_room on public.bm_answers(room_code,round_no);
alter table public.bm_rooms enable row level security;
alter table public.bm_players enable row level security;
alter table public.bm_answers enable row level security;
revoke all on public.bm_rooms,public.bm_players,public.bm_answers from anon,authenticated;
create or replace function public.bm_norm(t text) returns text language sql immutable as $$
 select regexp_replace(lower(trim(normalize(t,NFKC))), '[[:space:]　・･.．]+','','g')
$$;
create or replace function public.bm_create(p_code text,p_host text,p_name text,p_token text,p_total int,p_questions jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if p_code !~ '^[0-9]{6}$' or length(p_host)<24 or length(p_token)<24 or length(trim(p_name)) not between 1 and 20 or p_total not in (5,10,20) or jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions)<p_total or jsonb_array_length(p_questions)>100 then raise exception '入力が不正です'; end if;
 insert into bm_rooms(code,host_token,total,questions) values(p_code,p_host,p_total,p_questions);
 insert into bm_players(room_code,token,name) values(p_code,p_token,trim(p_name));
 return jsonb_build_object('ok',true);
exception when unique_violation then raise exception 'コードが重複しました。もう一度お試しください';
end $$;
create or replace function public.bm_join(p_code text,p_name text,p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r bm_rooms%rowtype;
begin
 select * into r from bm_rooms where code=p_code for update;
 if not found then raise exception 'ルームが見つかりません'; end if;
 if r.phase<>'lobby' then raise exception 'すでにゲームが始まっています'; end if;
 if (select count(*) from bm_players where room_code=p_code)>=8 then raise exception '満員です（最大8人）'; end if;
 if length(trim(p_name)) not between 1 and 20 or length(p_token)<24 then raise exception '名前を確認してください'; end if;
 if exists(select 1 from bm_players where room_code=p_code and lower(name)=lower(trim(p_name))) then raise exception '同じ名前の参加者がいます'; end if;
 insert into bm_players(room_code,token,name) values(p_code,p_token,trim(p_name));
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.bm_state(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r bm_rooms%rowtype; me bm_players%rowtype; n int; ready int; reveal boolean; plist jsonb; alist jsonb;
begin
 select * into me from bm_players where room_code=p_code and token=p_token;
 if not found then raise exception '参加情報が無効です'; end if;
 select * into r from bm_rooms where code=p_code;
 select count(*) into n from bm_players where room_code=p_code;
 select count(*) into ready from bm_answers where room_code=p_code and round_no=r.round_no;
 reveal := (r.phase in ('playing','finished') and ready=n);
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'score',score,'submitted',exists(select 1 from bm_answers a where a.player_id=p.id and a.round_no=r.round_no)) order by joined_at,id),'[]'::jsonb) into plist from bm_players p where room_code=p_code;
 if reveal then
 select coalesce(jsonb_agg(jsonb_build_object('id',a.player_id,'answer',a.answer) order by p.joined_at),'[]'::jsonb) into alist from bm_answers a join bm_players p on p.id=a.player_id where a.room_code=p_code and a.round_no=r.round_no;
 else alist:='[]'::jsonb; end if;
 return jsonb_build_object('phase',r.phase,'round',r.round_no,'total',r.total,'question',case when r.phase='lobby' then null else r.questions->>(r.round_no-1) end,'players',plist,'answers',alist,'reveal',reveal,'me',me.id,'host',r.host_token=p_token,'ready',ready,'unanimous',(reveal and (select count(distinct public.bm_norm(answer))=1 from bm_answers where room_code=p_code and round_no=r.round_no)),'success',(r.phase='finished' and (select count(distinct public.bm_norm(answer))=1 from bm_answers where room_code=p_code and round_no=r.round_no)));
end $$;
create or replace function public.bm_start(p_code text,p_token text)
returns void language plpgsql security definer set search_path=public as $$
declare r bm_rooms%rowtype;
begin
 select * into r from bm_rooms where code=p_code for update;
 if not found or r.host_token<>p_token then raise exception 'ホストのみ操作できます'; end if;
 if r.phase<>'lobby' then raise exception '開始済みです'; end if;
 if (select count(*) from bm_players where room_code=p_code)<2 then raise exception '2人以上必要です'; end if;
 update bm_rooms set phase='playing',round_no=1 where code=p_code;
end $$;
create or replace function public.bm_submit(p_code text,p_token text,p_answer text)
returns void language plpgsql security definer set search_path=public as $$
declare r bm_rooms%rowtype; pid uuid;
begin
 select * into r from bm_rooms where code=p_code for update;
 if not found or r.phase<>'playing' then raise exception '回答受付中ではありません'; end if;
 select id into pid from bm_players where room_code=p_code and token=p_token;
 if pid is null then raise exception '参加者ではありません'; end if;
 if length(trim(p_answer)) not between 1 and 60 then raise exception '回答は1〜60文字で入力してください'; end if;
 insert into bm_answers(room_code,round_no,player_id,answer) values(p_code,r.round_no,pid,trim(p_answer));
exception when unique_violation then raise exception 'すでに回答済みです';
end $$;
create or replace function public.bm_next(p_code text,p_token text)
returns void language plpgsql security definer set search_path=public as $$
declare r bm_rooms%rowtype; n int; ready int;
begin
 select * into r from bm_rooms where code=p_code for update;
 if not found or r.host_token<>p_token then raise exception 'ホストのみ操作できます'; end if;
 if r.phase<>'playing' then raise exception 'ゲームが進行中ではありません'; end if;
 select count(*) into n from bm_players where room_code=p_code;
 select count(*) into ready from bm_answers where room_code=p_code and round_no=r.round_no;
 if ready<>n then raise exception 'まだ全員の回答がそろっていません'; end if;
 if (select count(distinct public.bm_norm(answer))=1 from bm_answers where room_code=p_code and round_no=r.round_no) or r.round_no>=r.total then
   update bm_rooms set phase='finished' where code=p_code;
 else
   update bm_rooms set round_no=round_no+1 where code=p_code;
 end if;
end $$;
grant execute on function public.bm_create(text,text,text,text,int,jsonb),public.bm_join(text,text,text),public.bm_state(text,text),public.bm_start(text,text),public.bm_submit(text,text,text),public.bm_next(text,text) to anon,authenticated;
