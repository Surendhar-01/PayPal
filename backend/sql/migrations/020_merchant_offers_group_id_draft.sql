-- DRAFT ONLY: add the nullable group reference used by grouped offers.
-- Apply only after reviewing live schema shape and offer backfill counts.
-- This does not assign groups to demands or alter existing group/member rows.

BEGIN;

DO $preflight$
BEGIN
    IF to_regclass('public.merchant_offers') IS NULL
       OR to_regclass('public.demands') IS NULL
       OR to_regclass('public.demand_groups') IS NULL THEN
        RAISE EXCEPTION 'Offer group reference requires merchant_offers, demands, and demand_groups';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'merchant_offers'
          AND column_name = 'demand_id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'demands'
          AND column_name = 'group_id'
    ) THEN
        RAISE EXCEPTION 'Offer group reference backfill prerequisites are missing';
    END IF;
    LOCK TABLE public.demands, public.merchant_offers IN SHARE ROW EXCLUSIVE MODE;
END;
$preflight$;

ALTER TABLE public.merchant_offers
    ADD COLUMN IF NOT EXISTS group_id UUID;

DO $group_id_contract$
DECLARE
    v_udt_name TEXT;
    v_is_nullable TEXT;
    v_group_id_attnum SMALLINT;
    v_target_id_attnum SMALLINT;
BEGIN
    SELECT udt_name, is_nullable
    INTO v_udt_name, v_is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'merchant_offers'
      AND column_name = 'group_id';
    IF NOT FOUND OR v_udt_name <> 'uuid' OR v_is_nullable <> 'YES' THEN
        RAISE EXCEPTION 'merchant_offers.group_id must be nullable UUID';
    END IF;

    SELECT attnum INTO v_group_id_attnum
    FROM pg_attribute
    WHERE attrelid = 'public.merchant_offers'::regclass
      AND attname = 'group_id'
      AND NOT attisdropped;

        SELECT attnum INTO v_target_id_attnum
        FROM pg_attribute
        WHERE attrelid = 'public.demand_groups'::regclass
            AND attname = 'id'
            AND NOT attisdropped;

    IF EXISTS (
        SELECT 1 FROM pg_constraint AS constraint_info
        WHERE constraint_info.conrelid = 'public.merchant_offers'::regclass
          AND constraint_info.contype = 'f'
          AND v_group_id_attnum = ANY(constraint_info.conkey)
          AND (
              constraint_info.confrelid <> 'public.demand_groups'::regclass
              OR constraint_info.conkey <> ARRAY[v_group_id_attnum]::SMALLINT[]
              OR constraint_info.confkey <> ARRAY[v_target_id_attnum]::SMALLINT[]
              OR constraint_info.confdeltype <> 'r'
              OR NOT constraint_info.convalidated
          )
    ) THEN
        RAISE EXCEPTION 'Existing merchant_offers.group_id foreign key requires manual review';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint AS constraint_info
        WHERE constraint_info.conrelid = 'public.merchant_offers'::regclass
          AND constraint_info.contype = 'f'
          AND constraint_info.conkey = ARRAY[v_group_id_attnum]::SMALLINT[]
          AND constraint_info.confrelid = 'public.demand_groups'::regclass
          AND constraint_info.confkey = ARRAY[v_target_id_attnum]::SMALLINT[]
          AND constraint_info.confdeltype = 'r'
          AND constraint_info.convalidated
    ) THEN
        ALTER TABLE public.merchant_offers
            ADD CONSTRAINT merchant_offers_group_id_fkey
            FOREIGN KEY (group_id)
            REFERENCES public.demand_groups(id)
            ON DELETE RESTRICT;
    END IF;
END;
$group_id_contract$;

DO $backfill_safety$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.merchant_offers AS offer
        JOIN public.demands AS demand ON demand.id = offer.demand_id
        WHERE offer.group_id IS NOT NULL
          AND offer.group_id IS DISTINCT FROM demand.group_id
    ) THEN
        RAISE EXCEPTION 'Offer/demand group conflict: review assignments before backfill';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.merchant_offers AS offer
        LEFT JOIN public.demands AS demand ON demand.id = offer.demand_id
        WHERE COALESCE(offer.group_id, demand.group_id) IS NOT NULL
          AND offer.merchant_id IS NOT NULL
        GROUP BY COALESCE(offer.group_id, demand.group_id), offer.merchant_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Duplicate prospective group/merchant offers: manual review required';
    END IF;
END;
$backfill_safety$;

-- Backfill only offers whose linked demand already has a group. Unlinked and
-- ungrouped legacy offers remain NULL; existing non-NULL assignments are kept.
UPDATE public.merchant_offers AS offer
SET group_id = demand.group_id
FROM public.demands AS demand
WHERE offer.group_id IS NULL
  AND offer.demand_id = demand.id
  AND demand.group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_merchant_offers_group_merchant
    ON public.merchant_offers(group_id, merchant_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_merchant_offers_group_merchant
    ON public.merchant_offers(group_id, merchant_id)
    WHERE group_id IS NOT NULL AND merchant_id IS NOT NULL;

DO $group_merchant_index_contract$
DECLARE
    v_index_oid OID := to_regclass('public.uq_merchant_offers_group_merchant');
    v_table_oid OID;
    v_is_unique BOOLEAN;
    v_is_valid BOOLEAN;
    v_is_ready BOOLEAN;
    v_key_count SMALLINT;
    v_column_count SMALLINT;
    v_first_key TEXT;
    v_second_key TEXT;
    v_predicate TEXT;
BEGIN
    SELECT index_info.indrelid,
           index_info.indisunique,
           index_info.indisvalid,
           index_info.indisready,
           index_info.indnkeyatts,
           index_info.indnatts,
           pg_get_indexdef(index_info.indexrelid, 1, TRUE),
           pg_get_indexdef(index_info.indexrelid, 2, TRUE),
           regexp_replace(
               lower(pg_get_expr(index_info.indpred, index_info.indrelid)),
               '[[:space:]()]',
               '',
               'g'
           )
    INTO v_table_oid, v_is_unique, v_is_valid, v_is_ready,
         v_key_count, v_column_count, v_first_key, v_second_key, v_predicate
    FROM pg_index AS index_info
    WHERE index_info.indexrelid = v_index_oid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expected merchant offer group index is missing or is not an index';
    END IF;
     IF v_table_oid IS DISTINCT FROM 'public.merchant_offers'::regclass
         OR v_is_unique IS DISTINCT FROM TRUE
         OR v_is_valid IS DISTINCT FROM TRUE
         OR v_is_ready IS DISTINCT FROM TRUE
       OR v_key_count <> 2
       OR v_column_count <> 2
         OR v_first_key IS DISTINCT FROM 'group_id'
         OR v_second_key IS DISTINCT FROM 'merchant_id'
         OR v_predicate IS DISTINCT FROM 'group_idisnotnullandmerchant_idisnotnull' THEN
        RAISE EXCEPTION 'Existing uq_merchant_offers_group_merchant index has an unexpected definition';
    END IF;
END;
$group_merchant_index_contract$;

DROP POLICY IF EXISTS offers_select ON public.merchant_offers;
CREATE POLICY offers_select ON public.merchant_offers FOR SELECT USING (
    merchant_id = auth.uid()
   
    OR EXISTS (
        SELECT 1 FROM public.demands AS demand
        WHERE demand.id = merchant_offers.demand_id
          AND demand.customer_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM public.demand_group_members AS member
        WHERE member.group_id = merchant_offers.group_id
          AND member.customer_id = auth.uid()
          AND member.membership_status = 'active'
          AND member.removed_at IS NULL
    )
);

DROP POLICY IF EXISTS offers_insert ON public.merchant_offers;
CREATE POLICY offers_insert ON public.merchant_offers FOR INSERT WITH CHECK (
    public.is_admin()
    OR (
        merchant_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.profiles AS merchant
            WHERE merchant.id = auth.uid()
              AND merchant.role::TEXT = 'merchant'
        )
        AND (
            (group_id IS NULL AND (
                demand_id IS NULL
                OR EXISTS (
                    SELECT 1 FROM public.demands AS demand
                    WHERE demand.id = merchant_offers.demand_id
                      AND demand.group_id IS NULL
                )
            ))
            OR (
                group_id IS NOT NULL
                AND demand_id IS NOT NULL
                AND EXISTS (
                    SELECT 1
                    FROM public.demands AS demand
                    JOIN public.demand_groups AS demand_group
                      ON demand_group.id = demand.group_id
                    JOIN public.merchant_profiles AS merchant_profile
                      ON merchant_profile.id = auth.uid()
                    WHERE demand.id = merchant_offers.demand_id
                      AND demand.group_id = merchant_offers.group_id
                      AND merchant_profile.status = 'APPROVED'
                      AND demand_group.group_status = 'Approved'
                      AND demand_group.bidding_status = 'open'
                      AND (demand_group.bidding_start IS NULL OR demand_group.bidding_start <= now())
                      AND (demand_group.bidding_deadline IS NULL OR demand_group.bidding_deadline > now())
                )
            )
        )
    )
);

DROP POLICY IF EXISTS offers_update ON public.merchant_offers;
CREATE POLICY offers_update ON public.merchant_offers FOR UPDATE
    USING (
        public.is_admin()
        OR (
            merchant_id = auth.uid()
            AND EXISTS (
                SELECT 1 FROM public.profiles AS merchant
                WHERE merchant.id = auth.uid()
                  AND merchant.role::TEXT = 'merchant'
            )
        )
    )
    WITH CHECK (
        public.is_admin()
        OR (
            merchant_id = auth.uid()
            AND EXISTS (
                SELECT 1 FROM public.profiles AS merchant
                WHERE merchant.id = auth.uid()
                  AND merchant.role::TEXT = 'merchant'
            )
            AND (
                (group_id IS NULL AND (
                    demand_id IS NULL
                    OR EXISTS (
                        SELECT 1 FROM public.demands AS demand
                        WHERE demand.id = merchant_offers.demand_id
                          AND demand.group_id IS NULL
                    )
                ))
                OR (
                    group_id IS NOT NULL
                    AND demand_id IS NOT NULL
                    AND EXISTS (
                        SELECT 1
                        FROM public.demands AS demand
                        JOIN public.demand_groups AS demand_group
                          ON demand_group.id = demand.group_id
                        JOIN public.merchant_profiles AS merchant_profile
                          ON merchant_profile.id = auth.uid()
                        WHERE demand.id = merchant_offers.demand_id
                          AND demand.group_id = merchant_offers.group_id
                          AND merchant_profile.status = 'APPROVED'
                          AND demand_group.group_status = 'Approved'
                          AND demand_group.bidding_status = 'open'
                          AND (demand_group.bidding_start IS NULL OR demand_group.bidding_start <= now())
                          AND (demand_group.bidding_deadline IS NULL OR demand_group.bidding_deadline > now())
                    )
                )
            )
        )
    );

NOTIFY pgrst, 'reload schema';

COMMIT;