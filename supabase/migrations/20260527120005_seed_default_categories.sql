-- =============================================================================
-- 20260527120005_seed_default_categories.sql
-- =============================================================================
-- The 15 default categories every user starts with.
--
-- The UUIDs here MUST match `lib/core/database/default_categories.dart` —
-- the sync engine identifies rows across the Drift ⇄ Supabase boundary by
-- this id. Do NOT regenerate. New default categories get NEW uuids and a
-- new migration; never edit an existing row's id.
--
-- Colors are 32-bit ARGB decimal equivalents of the hex literals used in
-- Dart (e.g. 0xFF4CAF50 → 4283215696).
--
-- user_id is NULL — defaults are global. The RLS policy
-- `categories_select_default_or_own` lets every user read them.
-- =============================================================================

insert into public.categories
  (id, user_id, name, icon, color, is_custom, sort_order)
values
  ('11111111-1111-1111-1111-000000000001', null, 'Market',       'shopping_cart',     4283215696,  1),
  ('11111111-1111-1111-1111-000000000002', null, 'Restoran',     'restaurant',        4294918434,  2),
  ('11111111-1111-1111-1111-000000000003', null, 'Kahve',        'coffee',            4286141768,  3),
  ('11111111-1111-1111-1111-000000000004', null, 'Ulaşım',       'directions_bus',    4280391411,  4),
  ('11111111-1111-1111-1111-000000000005', null, 'Yakıt',        'local_gas_station', 4284513675,  5),
  ('11111111-1111-1111-1111-000000000006', null, 'Faturalar',    'receipt_long',      4288423856,  6),
  ('11111111-1111-1111-1111-000000000007', null, 'Kira',         'home',              4282557941,  7),
  ('11111111-1111-1111-1111-000000000008', null, 'Sağlık',       'medical_services',  4294198070,  8),
  ('11111111-1111-1111-1111-000000000009', null, 'Giyim',        'checkroom',         4293467747,  9),
  ('11111111-1111-1111-1111-000000000010', null, 'Eğlence',      'movie',             4294940672, 10),
  ('11111111-1111-1111-1111-000000000011', null, 'Elektronik',   'devices',           4278238676, 11),
  ('11111111-1111-1111-1111-000000000012', null, 'Spor',         'fitness_center',    4287349578, 12),
  ('11111111-1111-1111-1111-000000000013', null, 'Evcil Hayvan', 'pets',              4294961979, 13),
  ('11111111-1111-1111-1111-000000000014', null, 'Hediye',       'card_giftcard',     4291666392, 14),
  ('11111111-1111-1111-1111-000000000015', null, 'Diğer',        'more_horiz',        4288585374, 15)
on conflict (id) do nothing;
