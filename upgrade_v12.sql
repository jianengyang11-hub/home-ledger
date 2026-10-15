-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v12 · ติดตามเงินกู้และเงินให้ยืม
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- รันหลัง upgrade_v11.sql แล้ว รันซ้ำได้
-- ─────────────────────────────────────────────────────────────

create table if not exists public.loans (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  owner text not null references public.profiles(name) on update cascade on delete restrict,
  direction text not null check (direction in ('borrowed','lent')),
  counterparty text not null check (length(btrim(counterparty)) > 0),
  principal numeric not null check (principal > 0),
  code text not null check (code ~ '^[A-Z]{3}$'),
  started_on date not null default current_date,
  note text not null default ''
);

create index if not exists loans_owner_idx on public.loans (owner, started_on desc, id desc);

create table if not exists public.loan_payments (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  loan_id bigint not null references public.loans(id) on delete cascade,
  paid_on date not null default current_date,
  principal_paid numeric not null default 0 check (principal_paid >= 0),
  interest_paid numeric not null default 0 check (interest_paid >= 0),
  note text not null default '',
  check (principal_paid + interest_paid > 0)
);

create index if not exists loan_payments_loan_idx on public.loan_payments (loan_id, paid_on, id);

alter table public.loans enable row level security;
alter table public.loan_payments enable row level security;

drop policy if exists loans_select on public.loans;
create policy loans_select on public.loans
  for select to authenticated using (owner = public.my_name() or public.is_admin());

drop policy if exists loans_insert on public.loans;
create policy loans_insert on public.loans
  for insert to authenticated
  with check (owner = public.my_name() or public.is_admin());

drop policy if exists loans_update on public.loans;
drop policy if exists loans_delete on public.loans;

drop policy if exists loan_payments_select on public.loan_payments;
create policy loan_payments_select on public.loan_payments
  for select to authenticated
  using (exists (
    select 1 from public.loans l
    where l.id = loan_id and (l.owner = public.my_name() or public.is_admin())
  ));

drop policy if exists loan_payments_insert on public.loan_payments;
create policy loan_payments_insert on public.loan_payments
  for insert to authenticated
  with check (exists (
    select 1 from public.loans l
    where l.id = loan_id and (l.owner = public.my_name() or public.is_admin())
  ));

drop policy if exists loan_payments_delete on public.loan_payments;

create or replace function public.check_loan_principal_payment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  loan_principal numeric;
  already_paid numeric;
begin
  select principal into loan_principal
    from public.loans where id = new.loan_id for update;
  if loan_principal is null then
    raise exception 'ไม่พบรายการเงินกู้';
  end if;

  select coalesce(sum(principal_paid), 0) into already_paid
    from public.loan_payments where loan_id = new.loan_id;
  if already_paid + new.principal_paid > loan_principal then
    raise exception 'ยอดชำระเงินต้นเกินยอดเงินต้นคงเหลือ';
  end if;
  return new;
end $$;

drop trigger if exists loan_payment_principal_check on public.loan_payments;
create trigger loan_payment_principal_check
  before insert on public.loan_payments
  for each row execute function public.check_loan_principal_payment();

revoke update, delete on public.loan_payments from authenticated;
grant select, insert on public.loan_payments to authenticated;
revoke update, delete on public.loans from authenticated;
grant select, insert on public.loans to authenticated;
grant usage, select on sequence public.loans_id_seq to authenticated;
grant usage, select on sequence public.loan_payments_id_seq to authenticated;

notify pgrst, 'reload schema';

select
  exists (select 1 from information_schema.tables
           where table_schema = 'public' and table_name = 'loans') as "ตารางเงินกู้มีแล้ว",
  exists (select 1 from information_schema.tables
           where table_schema = 'public' and table_name = 'loan_payments') as "ตารางชำระคืนมีแล้ว",
  exists (select 1 from pg_trigger
           where tgname = 'loan_payment_principal_check'
             and tgrelid = to_regclass('public.loan_payments')) as "ตรวจยอดชำระเงินต้นแล้ว";
