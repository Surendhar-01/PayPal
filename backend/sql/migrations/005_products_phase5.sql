-- ==============================================================================
-- Migration 005: Phase 5 - Complete Product Catalogue & Product Management Integration
-- MarketTwin Demand-Driven Marketplace Platform
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Alter existing products table to support Phase 5 enterprise catalog specifications
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS model_number TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS specifications JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'piece';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS retail_price NUMERIC(12,2);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS wholesale_price NUMERIC(12,2);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS minimum_order_quantity INT NOT NULL DEFAULT 1;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS available_quantity INT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS images TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Backfill legacy column mappings if present
UPDATE public.products
SET retail_price = market_price
WHERE retail_price IS NULL AND market_price IS NOT NULL;

UPDATE public.products
SET wholesale_price = min_demand_price
WHERE wholesale_price IS NULL AND min_demand_price IS NOT NULL;

UPDATE public.products
SET specifications = specs
WHERE (specifications IS NULL OR specifications = '{}'::jsonb) AND specs IS NOT NULL;

UPDATE public.products
SET images = ARRAY[image_url]::TEXT[]
WHERE (images IS NULL OR images = ARRAY[]::TEXT[]) AND image_url IS NOT NULL;

UPDATE public.products
SET slug = lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substring(id::text from 1 for 6)
WHERE slug IS NULL;

-- Constraints
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_product_status;
ALTER TABLE public.products ADD CONSTRAINT chk_product_status CHECK (status IN ('active', 'inactive'));

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_product_retail_price;
ALTER TABLE public.products ADD CONSTRAINT chk_product_retail_price CHECK (retail_price >= 0);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_product_wholesale_price;
ALTER TABLE public.products ADD CONSTRAINT chk_product_wholesale_price CHECK (wholesale_price >= 0);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_product_moq;
ALTER TABLE public.products ADD CONSTRAINT chk_product_moq CHECK (minimum_order_quantity >= 1);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_products_slug ON public.products(slug);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_brand ON public.products(brand);
CREATE INDEX IF NOT EXISTS idx_products_status ON public.products(status);
CREATE INDEX IF NOT EXISTS idx_products_retail_price ON public.products(retail_price);
CREATE INDEX IF NOT EXISTS idx_products_created_at ON public.products(created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Security Policies
-- 1. Public & Customers & Merchants: Read active products only
DROP POLICY IF EXISTS products_read_active ON public.products;
CREATE POLICY products_read_active ON public.products
FOR SELECT
USING (
    status = 'active' OR
    (auth.jwt() ->> 'role' = 'admin') OR
    (public.is_admin())
);

-- 2. Admin: Full management (Create, Read all, Update, Delete)
DROP POLICY IF EXISTS products_admin_all ON public.products;
CREATE POLICY products_admin_all ON public.products
FOR ALL
USING (
    (auth.jwt() ->> 'role' = 'admin') OR
    (public.is_admin())
)
WITH CHECK (
    (auth.jwt() ->> 'role' = 'admin') OR
    (public.is_admin())
);

-- Storage bucket for product images
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage bucket RLS policies
DROP POLICY IF EXISTS "Public can view product images" ON storage.objects;
CREATE POLICY "Public can view product images" ON storage.objects
FOR SELECT
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Admin can upload product images" ON storage.objects;
CREATE POLICY "Admin can upload product images" ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'product-images' AND
    ((public.is_admin()))
);

DROP POLICY IF EXISTS "Admin can delete product images" ON storage.objects;
CREATE POLICY "Admin can delete product images" ON storage.objects
FOR DELETE
USING (
    bucket_id = 'product-images' AND
    ((public.is_admin()))
);

-- -----------------------------------------------------------------------------
-- Seed Initial Commercial Catalog Items (Active Products)
-- -----------------------------------------------------------------------------
INSERT INTO public.products (
    id, name, slug, description, category, brand, model_number,
    specifications, unit, retail_price, wholesale_price,
    minimum_order_quantity, available_quantity, images, status,
    sku, market_price, min_demand_price, in_stock, image_url, specs
) VALUES
(
    '11111111-1111-4111-a111-111111111111',
    'Industrial Grade Dual-Band IoT Gateway',
    'industrial-grade-dual-band-iot-gateway-igw01',
    'Ruggedized edge compute gateway designed for automated factory telemetry, SCADA systems, and harsh warehouse conditions. Features IP67 aluminum chassis, redundant dual Ethernet, and hardware watchdog timer.',
    'Industrial Hardware',
    'AcuEdge',
    'AE-GW-9000X',
    '{"Processor": "Quad-Core ARM Cortex-A53 1.5GHz", "RAM": "4GB LPDDR4 ECC", "Storage": "64GB eMMC 5.1", "Operating Temp": "-40C to +85C", "Ingress Protection": "IP67 Certified", "Interfaces": "2x Gigabit RJ45, 1x RS-485 Modbus, 2x USB 3.0"}'::jsonb,
    'unit',
    349.00,
    245.00,
    10,
    180,
    ARRAY['https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'AE-GW-9000X',
    349.00,
    245.00,
    TRUE,
    'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&w=800&q=80',
    '{"Processor": "Quad-Core ARM Cortex-A53", "Operating Temp": "-40C to +85C"}'::jsonb
),
(
    '22222222-2222-4222-a222-222222222222',
    'Precision Ultrasonic Flow Meter & Sensor',
    'precision-ultrasonic-flow-meter-sensor-ufm02',
    'Non-invasive transit-time clamp-on ultrasonic flow meter for industrial fluid monitoring. Suitable for pipes from 15mm to 6000mm diameter with accuracy within +/- 1.0%. Zero pressure drop.',
    'Instrumentation',
    'FlowMetric',
    'FM-US-620',
    '{"Pipe Diameter": "DN15 to DN6000", "Accuracy": "+/- 1.0% of reading", "Output Signals": "4-20mA, OCT Pulse, Relay, RS485 Modbus", "Fluid Temperature": "-30C to 160C", "Enclosure": "Die-cast Aluminum NEMA 4X"}'::jsonb,
    'set',
    780.00,
    560.00,
    5,
    95,
    ARRAY['https://images.unsplash.com/photo-1581092160607-ee22621dd758?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'FM-US-620',
    780.00,
    560.00,
    TRUE,
    'https://images.unsplash.com/photo-1581092160607-ee22621dd758?auto=format&fit=crop&w=800&q=80',
    '{"Accuracy": "+/- 1.0%", "Pipe Range": "DN15 - DN6000"}'::jsonb
),
(
    '33333333-3333-4333-a333-333333333333',
    'Commercial LiFePO4 Energy Storage Module 48V 100Ah',
    'commercial-lifepo4-energy-storage-module-48v-100ah',
    'High-cycle lithium iron phosphate rack-mount storage battery for microgrids, telecom backup, and commercial solar installations. Over 6000 charge cycles at 80% DoD with integrated smart BMS.',
    'Energy & Power',
    'VoltStore',
    'VS-48100-RM',
    '{"Nominal Voltage": "51.2V", "Capacity": "100Ah / 5.12kWh", "Cycle Life": ">6000 cycles @ 0.5C 80% DoD", "Max Charge Current": "100A", "Communication": "CAN 2.0B / RS485 BMS Uplink", "Mounting": "19-inch 3U Standard Rack"}'::jsonb,
    'module',
    1450.00,
    1080.00,
    4,
    60,
    ARRAY['https://images.unsplash.com/photo-1509391365360-2e959784a276?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'VS-48100-RM',
    1450.00,
    1080.00,
    TRUE,
    'https://images.unsplash.com/photo-1509391365360-2e959784a276?auto=format&fit=crop&w=800&q=80',
    '{"Capacity": "5.12kWh", "Cycle Life": ">6000 cycles"}'::jsonb
),
(
    '44444444-4444-4444-a444-444444444444',
    'High-Torque NEMA 34 Closed-Loop Stepper Kit',
    'high-torque-nema-34-closed-loop-stepper-kit',
    'Integrated hybrid closed-loop servo motor kit with DSP digital driver and 1000-line optical encoder. Zero loss of steps, rapid acceleration, and minimal heating for CNC milling and robotic automation.',
    'Automation & Robotics',
    'MotionPro',
    'MP-86HBM-8N',
    '{"Holding Torque": "8.5 N.m (1204 oz.in)", "Shaft Diameter": "14mm Keyway", "Encoder Resolution": "1000 CPR (4000 PPR)", "Driver Input": "AC 20-80V / DC 30-110V", "Max Step Pulse Frequency": "200 kHz"}'::jsonb,
    'kit',
    220.00,
    165.00,
    8,
    220,
    ARRAY['https://images.unsplash.com/photo-1581092335397-9583fe92d232?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'MP-86HBM-8N',
    220.00,
    165.00,
    TRUE,
    'https://images.unsplash.com/photo-1581092335397-9583fe92d232?auto=format&fit=crop&w=800&q=80',
    '{"Holding Torque": "8.5 N.m", "Encoder": "1000 CPR"}'::jsonb
),
(
    '55555555-5555-4555-a555-555555555555',
    'Enterprise 10G SFP+ Managed Fiber Switch 24-Port',
    'enterprise-10g-sfp-managed-fiber-switch-24-port',
    'Enterprise Layer 3 aggregation switch featuring 24x 10G SFP+ optical ports and 2x 40G QSFP+ uplink ports. Wire-speed switching fabric with redundant hot-swap AC power supplies.',
    'Networking & Telecom',
    'OptiNet Core',
    'ON-SW-24X10',
    '{"Switching Capacity": "640 Gbps", "Forwarding Rate": "476 Mpps", "Ports": "24x 10G SFP+, 2x 40G QSFP+", "L3 Routing": "Static, OSPF v2/v3, BGP4, VRRP", "Power": "Dual 1+1 Redundant 100-240V AC"}'::jsonb,
    'unit',
    890.00,
    640.00,
    2,
    45,
    ARRAY['https://images.unsplash.com/photo-1544197150-b99a580bb7a8?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'ON-SW-24X10',
    890.00,
    640.00,
    TRUE,
    'https://images.unsplash.com/photo-1544197150-b99a580bb7a8?auto=format&fit=crop&w=800&q=80',
    '{"Switching": "640 Gbps", "Ports": "24x 10G SFP+"}'::jsonb
),
(
    '66666666-6666-4666-a666-666666666666',
    'Medical-Grade High-Precision Peristaltic Pump',
    'medical-grade-high-precision-peristaltic-pump',
    'Micro-volume precision laboratory and pharmaceutical dispensing pump with calibrated 4-roller rotor and stepper motor drive. Flow range from 0.007 mL/min to 380 mL/min.',
    'Medical & Lab Equipment',
    'BioDose',
    'BD-PP-400X',
    '{"Flow Rate": "0.007 - 380 mL/min", "Dispense Accuracy": "< 0.5%", "Speed Range": "0.1 - 350 rpm (0.1 rpm res)", "Tubing Compatibility": "Silicon, PharMed, Norprene", "Control Interface": "RS485 Modbus, 0-10V, Touchscreen"}'::jsonb,
    'unit',
    520.00,
    380.00,
    3,
    80,
    ARRAY['https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80']::TEXT[],
    'active',
    'BD-PP-400X',
    520.00,
    380.00,
    TRUE,
    'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80',
    '{"Accuracy": "< 0.5%", "Flow Range": "0.007 - 380 mL/min"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    brand = EXCLUDED.brand,
    model_number = EXCLUDED.model_number,
    specifications = EXCLUDED.specifications,
    unit = EXCLUDED.unit,
    retail_price = EXCLUDED.retail_price,
    wholesale_price = EXCLUDED.wholesale_price,
    minimum_order_quantity = EXCLUDED.minimum_order_quantity,
    available_quantity = EXCLUDED.available_quantity,
    images = EXCLUDED.images,
    status = EXCLUDED.status,
    market_price = EXCLUDED.market_price,
    min_demand_price = EXCLUDED.min_demand_price,
    image_url = EXCLUDED.image_url,
    specs = EXCLUDED.specs;
