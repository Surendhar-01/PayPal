-- MarketTwin Supabase schema
-- Safe to run multiple times (uses IF NOT EXISTS / guarded enum creation).

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums (guarded)
DO $$ BEGIN CREATE TYPE user_role AS ENUM ('customer','merchant'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE demand_status AS ENUM ('Pending','Grouped','Offers Received','Approved','Completed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE demand_group_status AS ENUM ('Forming','Open for Bidding','Reviewing Offers','Finalized'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE offer_status AS ENUM ('Submitted','Under Review','Customer Approved','Rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE order_status AS ENUM ('Approved','Processing','Dispatched','Delivered','Cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Profiles (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE,
    full_name TEXT,
    role user_role NOT NULL DEFAULT 'customer',
    company TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_profiles (
    id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    tax_id TEXT,
    address TEXT,
    phone TEXT,
    status TEXT NOT NULL DEFAULT 'Active',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_profiles (
    id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    contact_name TEXT,
    category TEXT,
    rating NUMERIC(3,2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'Under Review',
    factory_location TEXT,
    verified_tier TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    sku TEXT UNIQUE NOT NULL,
    description TEXT,
    market_price NUMERIC(12,2) NOT NULL,
    min_demand_price NUMERIC(12,2),
    rating NUMERIC(3,2) NOT NULL DEFAULT 0,
    reviews_count INT NOT NULL DEFAULT 0,
    in_stock BOOLEAN NOT NULL DEFAULT TRUE,
    image_url TEXT,
    specs JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.demand_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_code TEXT UNIQUE NOT NULL,
    product_title TEXT NOT NULL,
    category TEXT NOT NULL,
    total_quantity INT NOT NULL DEFAULT 0,
    threshold_quantity INT NOT NULL,
    participants_count INT NOT NULL DEFAULT 0,
    estimated_savings NUMERIC(12,2) NOT NULL DEFAULT 0,
    status demand_group_status NOT NULL DEFAULT 'Forming',
    deadline DATE,
    lowest_offer_price NUMERIC(12,2),
    offers_count INT NOT NULL DEFAULT 0,
    top_offer_merchant TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.demands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demand_code TEXT UNIQUE NOT NULL,
    customer_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    target_price NUMERIC(12,2) NOT NULL,
    market_price NUMERIC(12,2),
    target_quantity INT NOT NULL,
    current_group_quantity INT NOT NULL DEFAULT 0,
    group_threshold INT,
    status demand_status NOT NULL DEFAULT 'Pending',
    description TEXT,
    specs JSONB NOT NULL DEFAULT '{}'::jsonb,
    deadline DATE,
    group_id UUID REFERENCES public.demand_groups(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.demand_group_members (
    group_id UUID NOT NULL REFERENCES public.demand_groups(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    quantity_committed INT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, customer_id)
);

CREATE TABLE IF NOT EXISTS public.merchant_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_code TEXT UNIQUE NOT NULL,
    demand_id UUID REFERENCES public.demands(id) ON DELETE CASCADE,
    demand_title TEXT,
    merchant_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    merchant_name TEXT,
    merchant_rating NUMERIC(3,2),
    unit_price NUMERIC(12,2) NOT NULL,
    original_target_price NUMERIC(12,2),
    total_offer_amount NUMERIC(12,2),
    min_order_quantity INT,
    delivery_days INT,
    warranty_months INT,
    status offer_status NOT NULL DEFAULT 'Submitted',
    spec_notes TEXT,
    shipping_terms TEXT,
    submitted_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number TEXT UNIQUE NOT NULL,
    demand_id UUID REFERENCES public.demands(id) ON DELETE SET NULL,
    demand_code TEXT,
    customer_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    product_name TEXT,
    merchant_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    merchant_name TEXT,
    quantity INT NOT NULL DEFAULT 1,
    total_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    status order_status NOT NULL DEFAULT 'Approved',
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    estimated_delivery DATE,
    tracking_number TEXT,
    carrier TEXT,
    current_step INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    type TEXT NOT NULL CHECK (type IN ('demand','offer','order','system')),
    unread BOOLEAN NOT NULL DEFAULT TRUE,
    action_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_demands_customer ON public.demands(customer_id);
CREATE INDEX IF NOT EXISTS idx_demands_group ON public.demands(group_id);
CREATE INDEX IF NOT EXISTS idx_offers_demand ON public.merchant_offers(demand_id);
CREATE INDEX IF NOT EXISTS idx_offers_merchant ON public.merchant_offers(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant ON public.orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);

-- Auth trigger: create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role user_role;
BEGIN
    v_role := COALESCE(
        CASE
            WHEN NEW.raw_user_meta_data->>'role' IN ('customer', 'merchant')
            THEN (NEW.raw_user_meta_data->>'role')::user_role
            ELSE NULL
        END,
        'customer'
    );
    INSERT INTO public.profiles (id, email, full_name, role, company)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        v_role,
        NEW.raw_user_meta_data->>'company'
    )
    ON CONFLICT (id) DO NOTHING;

    IF v_role = 'customer' THEN
        INSERT INTO public.customer_profiles (id) VALUES (NEW.id) ON CONFLICT (id) DO NOTHING;
    ELSIF v_role = 'merchant' THEN
        INSERT INTO public.merchant_profiles (id, contact_name, category)
        VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), NEW.raw_user_meta_data->>'category')
        ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demand_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demand_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Policies: profiles
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles FOR INSERT WITH CHECK (id = auth.uid());

-- customer_profiles
DROP POLICY IF EXISTS customer_profiles_select ON public.customer_profiles;
CREATE POLICY customer_profiles_select ON public.customer_profiles FOR SELECT USING (id = auth.uid());
DROP POLICY IF EXISTS customer_profiles_update ON public.customer_profiles;
CREATE POLICY customer_profiles_update ON public.customer_profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS customer_profiles_insert ON public.customer_profiles;
CREATE POLICY customer_profiles_insert ON public.customer_profiles FOR INSERT WITH CHECK (id = auth.uid());

-- merchant_profiles
DROP POLICY IF EXISTS merchant_profiles_select ON public.merchant_profiles;
CREATE POLICY merchant_profiles_select ON public.merchant_profiles FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS merchant_profiles_update ON public.merchant_profiles;
CREATE POLICY merchant_profiles_update ON public.merchant_profiles FOR UPDATE USING (id = auth.uid());
DROP POLICY IF EXISTS merchant_profiles_insert ON public.merchant_profiles;
CREATE POLICY merchant_profiles_insert ON public.merchant_profiles FOR INSERT WITH CHECK (id = auth.uid());

-- products (public read)
DROP POLICY IF EXISTS products_select ON public.products;
CREATE POLICY products_select ON public.products FOR SELECT USING (TRUE);

-- demand_groups (authenticated read)
DROP POLICY IF EXISTS demand_groups_select ON public.demand_groups;
CREATE POLICY demand_groups_select ON public.demand_groups FOR SELECT USING (auth.uid() IS NOT NULL);

-- demands
DROP POLICY IF EXISTS demands_select ON public.demands;
CREATE POLICY demands_select ON public.demands FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS demands_insert ON public.demands;
CREATE POLICY demands_insert ON public.demands FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS demands_update ON public.demands;
CREATE POLICY demands_update ON public.demands FOR UPDATE USING (customer_id = auth.uid());
DROP POLICY IF EXISTS demands_delete ON public.demands;
CREATE POLICY demands_delete ON public.demands FOR DELETE USING (customer_id = auth.uid());

-- demand_group_members
DROP POLICY IF EXISTS dgm_select ON public.demand_group_members;
CREATE POLICY dgm_select ON public.demand_group_members FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS dgm_insert ON public.demand_group_members;
CREATE POLICY dgm_insert ON public.demand_group_members FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS dgm_update ON public.demand_group_members;
CREATE POLICY dgm_update ON public.demand_group_members FOR UPDATE USING (customer_id = auth.uid());
DROP POLICY IF EXISTS dgm_delete ON public.demand_group_members;
CREATE POLICY dgm_delete ON public.demand_group_members FOR DELETE USING (customer_id = auth.uid());

-- offers
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

-- orders
DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders FOR SELECT USING (
    customer_id = auth.uid() OR merchant_id = auth.uid()
);
DROP POLICY IF EXISTS orders_insert ON public.orders;
CREATE POLICY orders_insert ON public.orders FOR INSERT WITH CHECK (customer_id = auth.uid());
DROP POLICY IF EXISTS orders_update ON public.orders;
CREATE POLICY orders_update ON public.orders FOR UPDATE USING (merchant_id = auth.uid());

-- notifications
DROP POLICY IF EXISTS notifications_select ON public.notifications;
CREATE POLICY notifications_select ON public.notifications FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_insert ON public.notifications;
CREATE POLICY notifications_insert ON public.notifications FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_update ON public.notifications;
CREATE POLICY notifications_update ON public.notifications FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_delete ON public.notifications;
CREATE POLICY notifications_delete ON public.notifications FOR DELETE USING (user_id = auth.uid());