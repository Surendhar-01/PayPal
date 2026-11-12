CREATE TABLE IF NOT EXISTS public.order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    status_message TEXT,
    location TEXT,
    updated_by UUID REFERENCES public.profiles(id),
    actor_role TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shipments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_reference TEXT UNIQUE NOT NULL,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    merchant_id UUID REFERENCES public.profiles(id),
    logistics_provider TEXT,
    tracking_number TEXT,
    shipment_status TEXT NOT NULL DEFAULT 'Created',
    dispatch_date TIMESTAMPTZ,
    estimated_delivery_date TIMESTAMPTZ,
    actual_delivery_date TIMESTAMPTZ,
    delivery_method TEXT,
    shipping_remarks TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shipment_tracking_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id UUID NOT NULL REFERENCES public.shipments(id) ON DELETE CASCADE,
    event_type TEXT,
    event_description TEXT,
    location TEXT,
    event_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.delivery_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    shipment_id UUID REFERENCES public.shipments(id) ON DELETE SET NULL,
    document_type TEXT,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    uploaded_by UUID REFERENCES public.profiles(id),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.delivery_confirmations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    confirmation_status TEXT NOT NULL DEFAULT 'Awaiting Customer Confirmation',
    confirmed_at TIMESTAMPTZ,
    customer_remarks TEXT,
    proof_file_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON public.order_status_history(order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_order ON public.shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipment_events_shipment ON public.shipment_tracking_events(shipment_id);
CREATE INDEX IF NOT EXISTS idx_delivery_documents_order ON public.delivery_documents(order_id);
CREATE INDEX IF NOT EXISTS idx_delivery_confirmations_order ON public.delivery_confirmations(order_id);

-- RLS
ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_tracking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_confirmations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS osh_select ON public.order_status_history;
CREATE POLICY osh_select ON public.order_status_history FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_status_history.order_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);

DROP POLICY IF EXISTS shipments_select ON public.shipments;
CREATE POLICY shipments_select ON public.shipments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);

DROP POLICY IF EXISTS ste_select ON public.shipment_tracking_events;
CREATE POLICY ste_select ON public.shipment_tracking_events FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.shipments s JOIN public.orders o ON o.id = s.order_id WHERE s.id = shipment_tracking_events.shipment_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);

DROP POLICY IF EXISTS dd_select ON public.delivery_documents;
CREATE POLICY dd_select ON public.delivery_documents FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = delivery_documents.order_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);

DROP POLICY IF EXISTS dc_select ON public.delivery_confirmations;
CREATE POLICY dc_select ON public.delivery_confirmations FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS dc_insert ON public.delivery_confirmations;
CREATE POLICY dc_insert ON public.delivery_confirmations FOR INSERT WITH CHECK (customer_id = auth.uid());