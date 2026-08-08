create policy devices_self_insert on public.user_devices
for insert to authenticated
with check (user_id = auth.uid());

create policy devices_self_update on public.user_devices
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy devices_self_delete on public.user_devices
for delete to authenticated
using (user_id = auth.uid());
