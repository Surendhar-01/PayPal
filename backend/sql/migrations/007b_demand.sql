

ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS model_number TEXT;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS dimensions JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS certifications JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS technical_specifications JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'units';
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS maximum_budget NUMERIC(12,2);
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS expected_lead_time INTEGER;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS delivery_address JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS additional_requirements TEXT;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Ensure status default
ALTER TABLE public.demands ALTER COLUMN status SET DEFAULT 'Submitted';

CREATE TABLE IF NOT EXISTS public.demand_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demand_id UUID NOT NULL REFERENCES public.demands(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_type TEXT,
    file_size BIGINT,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_demand_attachments_demand ON public.demand_attachments(demand_id);
CREATE INDEX IF NOT EXISTS idx_demands_customer_status ON public.demands(customer_id, status);

-- RLS
ALTER TABLE public.demand_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS demand_attachments_select ON public.demand_attachments;
CREATE POLICY demand_attachments_select ON public.demand_attachments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.demands d WHERE d.id = demand_attachments.demand_id AND (d.customer_id = auth.uid()))
);

DROP POLICY IF EXISTS demand_attachments_insert ON public.demand_attachments;
CREATE POLICY demand_attachments_insert ON public.demand_attachments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.demands d WHERE d.id = demand_attachments.demand_id AND d.customer_id = auth.uid())
);

DROP POLICY IF EXISTS demand_attachments_delete ON public.demand_attachments;
CREATE POLICY demand_attachments_delete ON public.demand_attachments FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.demands d WHERE d.id = demand_attachments.demand_id AND d.customer_id = auth.uid())
);