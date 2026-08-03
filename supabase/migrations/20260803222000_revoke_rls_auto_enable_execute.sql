-- The event trigger invokes this function internally. Client roles never need
-- to call the SECURITY DEFINER function through the public RPC endpoint.
revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.rls_auto_enable() from anon;
revoke execute on function public.rls_auto_enable() from authenticated;
