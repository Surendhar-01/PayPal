ALTER TABLE public.demand_groups ADD COLUMN IF NOT EXISTS bidding_status TEXT NOT NULL DEFAULT 'closed';
ALTER TABLE public.demand_groups ADD COLUMN IF NOT EXISTS bidding_start TIMESTAMPTZ;
ALTER TABLE public.demand_groups ADD COLUMN IF NOT EXISTS bidding_deadline TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.merchant_offer_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_type TEXT,
    file_size BIGINT,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchant_offer_attachments_offer ON public.merchant_offer_attachments(offer_id);

ALTER TABLE public.merchant_offer_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moa_select ON public.merchant_offer_attachments;
CREATE POLICY moa_select ON public.merchant_offer_attachments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = merchant_offer_attachments.offer_id AND (o.merchant_id = auth.uid()))
);

DROP POLICY IF EXISTS moa_insert ON public.merchant_offer_attachments;
CREATE POLICY moa_insert ON public.merchant_offer_attachments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = merchant_offer_attachments.offer_id AND o.merchant_id = auth.uid())
);

-- offer status history
CREATE TABLE IF NOT EXISTS public.offer_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    changed_by UUID REFERENCES public.profiles(id),
    remarks TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);