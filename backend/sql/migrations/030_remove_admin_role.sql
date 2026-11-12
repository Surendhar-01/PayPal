-- ==============================================================================
-- Migration 030: Remove Admin role and Admin-only access paths
-- MarketTwin Demand-Driven Marketplace Platform
-- ==============================================================================
--
-- Removes the Admin role from the platform. Only Customer and Merchant roles
-- remain. Customer and merchant data-ownership rules are preserved, and
-- Admin-only tables, policies and helper functions are dropped.
--
-- This migration is idempotent and safe to re-run.

-- 1. Rebuild the user_role enum without the 'admin' label.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'user_role' AND e.enumlabel = 'admin'
    ) THEN
        CREATE TYPE public.user_role_without_admin AS ENUM ('customer', 'merchant');
        ALTER TABLE public.profiles
            ALTER COLUMN role TYPE public.user_role_without_admin
            USING CASE
                WHEN public.profiles.role::text IN ('customer', 'merchant')
                THEN public.profiles.role::text::public.user_role_without_admin
                ELSE 'customer'::public.user_role_without_admin
            END;
        ALTER TABLE public.user_roles
            ALTER COLUMN role TYPE public.user_role_without_admin
            USING CASE
                WHEN public.user_roles.role::text IN ('customer', 'merchant')
                THEN public.user_roles.role::text::public.user_role_without_admin
                ELSE 'customer'::public.user_role_without_admin
            END;
        DROP TYPE public.user_role;
        ALTER TYPE public.user_role_without_admin RENAME TO user_role;
    END IF;
END
$$;

-- 2. Drop Admin-only application tables (no Customer/Merchant functionality
--    depends on them after the Admin removal).
DROP TABLE IF EXISTS public.user_roles;
DROP TABLE IF EXISTS public.platform_settings;
DROP TABLE IF EXISTS public.audit_logs;

-- 3. Drop Admin-only policies and replace Admin-based access rules with
--    Customer/Merchant owner-based ownership rules.

-- profiles: owner-only access.
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles FOR INSERT WITH CHECK (id = auth.uid());

-- customer_profiles: owner-only access.
DROP POLICY IF EXISTS customer_profiles_select ON public.customer_profiles;
CREATE POLICY customer_profiles_select ON public.customer_profiles FOR SELECT USING (id = auth.uid());
DROP POLICY IF EXISTS customer_profiles_update ON public.customer_profiles;
CREATE POLICY customer_profiles_update ON public.customer_profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS customer_profiles_insert ON public.customer_profiles;
CREATE POLICY customer_profiles_insert ON public.customer_profiles FOR INSERT WITH CHECK (id = auth.uid());

-- merchant_profiles: owner-only updates; public read retained.
DROP POLICY IF EXISTS merchant_profiles_update ON public.merchant_profiles;
CREATE POLICY merchant_profiles_update ON public.merchant_profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS merchant_profiles_insert ON public.merchant_profiles;
CREATE POLICY merchant_profiles_insert ON public.merchant_profiles FOR INSERT WITH CHECK (id = auth.uid());

-- merchant_verifications: merchants read their own verification status.
DROP POLICY IF EXISTS merchant_verifications_write ON public.merchant_verifications;
CREATE POLICY merchant_verifications_select ON public.merchant_verifications FOR SELECT USING (merchant_id = auth.uid());

-- offers: merchants manage their own offers; customers review offers for their demands.
DROP POLICY IF EXISTS offers_select ON public.merchant_offers;
CREATE POLICY offers_select ON public.merchant_offers FOR SELECT USING (
    merchant_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.demands d WHERE d.id = merchant_offers.demand_id AND d.customer_id = auth.uid())
);
DROP POLICY IF EXISTS offers_insert ON public.merchant_offers;
CREATE POLICY offers_insert ON public.merchant_offers FOR INSERT WITH CHECK (merchant_id = auth.uid());
DROP POLICY IF EXISTS offers_update ON public.merchant_offers;
CREATE POLICY offers_update ON public.merchant_offers FOR UPDATE USING (merchant_id = auth.uid());
DROP POLICY IF EXISTS offers_delete ON public.merchant_offers;
CREATE POLICY offers_delete ON public.merchant_offers FOR DELETE USING (merchant_id = auth.uid());

-- orders: customers manage their own orders; merchants update fulfillment state.
DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders FOR SELECT USING (
    customer_id = auth.uid() OR merchant_id = auth.uid()
);
DROP POLICY IF EXISTS orders_insert ON public.orders;
CREATE POLICY orders_insert ON public.orders FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS orders_update ON public.orders;
CREATE POLICY orders_update ON public.orders FOR UPDATE USING (merchant_id = auth.uid());

-- notifications: users manage only their own notifications.
DROP POLICY IF EXISTS notifications_select ON public.notifications;
CREATE POLICY notifications_select ON public.notifications FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_insert ON public.notifications;
CREATE POLICY notifications_insert ON public.notifications FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_update ON public.notifications;
CREATE POLICY notifications_update ON public.notifications FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_delete ON public.notifications;
CREATE POLICY notifications_delete ON public.notifications FOR DELETE USING (user_id = auth.uid());

-- demands: customers manage only their own demands.
DROP POLICY IF EXISTS demands_select ON public.demands;
CREATE POLICY demands_select ON public.demands FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS demands_insert ON public.demands;
CREATE POLICY demands_insert ON public.demands FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS demands_update ON public.demands;
CREATE POLICY demands_update ON public.demands FOR UPDATE USING (customer_id = auth.uid());
DROP POLICY IF EXISTS demands_delete ON public.demands;
CREATE POLICY demands_delete ON public.demands FOR DELETE USING (customer_id = auth.uid());

-- demand group membership: customers manage only their own memberships.
DROP POLICY IF EXISTS dgm_select ON public.demand_group_members;
CREATE POLICY dgm_select ON public.demand_group_members FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS dgm_insert ON public.demand_group_members;
CREATE POLICY dgm_insert ON public.demand_group_members FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS dgm_update ON public.demand_group_members;
CREATE POLICY dgm_update ON public.demand_group_members FOR UPDATE USING (customer_id = auth.uid());
DROP POLICY IF EXISTS dgm_delete ON public.demand_group_members;
CREATE POLICY dgm_delete ON public.demand_group_members FOR DELETE USING (customer_id = auth.uid());

-- merchant catalog categories: merchants manage only their own catalog entries.
DROP POLICY IF EXISTS merchant_categories_write ON public.merchant_categories;
CREATE POLICY merchant_categories_write ON public.merchant_categories FOR ALL USING (merchant_id = auth.uid()) WITH CHECK (merchant_id = auth.uid());

-- 4. Drop remaining Admin-only policies.
DROP POLICY IF EXISTS products_admin_all ON public.products;
DROP POLICY IF EXISTS demand_groups_write ON public.demand_groups;
DROP POLICY IF EXISTS normalized_requirements_admin_all ON public.demand_normalized_requirements;
DROP POLICY IF EXISTS categories_write ON public.categories;
DROP POLICY IF EXISTS product_images_write ON public.product_images;
DROP POLICY IF EXISTS order_items_write ON public.order_items;
DROP POLICY IF EXISTS payments_write ON public.payments;
DROP POLICY IF EXISTS payment_events_admin ON public.payment_events;
DROP POLICY IF EXISTS platform_settings_admin ON public.platform_settings;
DROP POLICY IF EXISTS audit_logs_insert ON public.audit_logs;
DROP POLICY IF EXISTS audit_logs_select ON public.audit_logs;
DROP POLICY IF EXISTS user_roles_write ON public.user_roles;
DROP POLICY IF EXISTS demand_group_reviews_admin ON public.demand_group_reviews;
DROP POLICY IF EXISTS demand_group_runs_admin ON public.demand_group_runs;
DROP POLICY IF EXISTS demand_group_family_aliases_admin ON public.demand_group_family_aliases;
DROP POLICY IF EXISTS demand_group_merge_requests_admin_write ON public.demand_group_merge_requests;
DROP POLICY IF EXISTS coe_write ON public.customer_offer_eligibility;
DROP POLICY IF EXISTS cos_write ON public.customer_offer_selections;
DROP POLICY IF EXISTS och_select ON public.offer_comparison_history;
DROP POLICY IF EXISTS dc_select ON public.delivery_confirmations;

-- Storage: drop Admin-only product image upload/delete policies.
DROP POLICY IF EXISTS "Admin can upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Admin can delete product images" ON storage.objects;

-- 5. Drop the Admin helper function.
DROP FUNCTION IF EXISTS public.is_admin();
