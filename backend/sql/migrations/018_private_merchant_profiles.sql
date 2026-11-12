-- Merchant profile records contain private business and contact details.
-- A merchant may read only their own record; admins retain authorized access.
DROP POLICY IF EXISTS merchant_profiles_select ON public.merchant_profiles;
CREATE POLICY merchant_profiles_select ON public.merchant_profiles
FOR SELECT USING (
    id = auth.uid()
   
);
