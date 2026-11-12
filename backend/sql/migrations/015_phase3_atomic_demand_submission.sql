-- Phase 3 demand contract: preserve legacy values while adding explicit price
-- bounds, fractional quantities, and retry-safe submission identifiers.
ALTER TABLE public.demands
    ALTER COLUMN target_quantity TYPE NUMERIC USING target_quantity::NUMERIC,
    ALTER COLUMN target_price DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS min_target_unit_price NUMERIC,
    ADD COLUMN IF NOT EXISTS max_target_unit_price NUMERIC,
    ADD COLUMN IF NOT EXISTS submission_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS demands_submission_id_key
    ON public.demands (submission_id)
    WHERE submission_id IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.demands'::regclass
          AND conname = 'demands_target_price_range_check'
    ) THEN
        ALTER TABLE public.demands
            ADD CONSTRAINT demands_target_price_range_check
            CHECK (
                (min_target_unit_price IS NULL AND max_target_unit_price IS NULL)
                OR (
                    min_target_unit_price > 0
                    AND max_target_unit_price >= min_target_unit_price
                )
            );
    END IF;
END
$$;

DROP POLICY IF EXISTS demands_select ON public.demands;
CREATE POLICY demands_select ON public.demands
    FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS demand_requirements_select ON public.demand_requirements;
CREATE POLICY demand_requirements_select ON public.demand_requirements
    FOR SELECT USING (
        public.is_admin()
        OR EXISTS (
            SELECT 1
            FROM public.demands d
            WHERE d.id = demand_requirements.demand_id
              AND d.customer_id = auth.uid()
        )
    );

CREATE OR REPLACE FUNCTION public.create_customer_demand_v1(
    p_submission_id UUID,
    p_demand JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_customer_id UUID;
    v_quantity NUMERIC;
    v_min_price NUMERIC;
    v_max_price NUMERIC;
    v_code TEXT;
    v_attempt INTEGER;
    v_saved public.demands%ROWTYPE;
    v_normalized JSONB;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'This operation requires the backend service role'
            USING ERRCODE = '42501';
    END IF;
    IF p_submission_id IS NULL OR p_demand IS NULL THEN
        RAISE EXCEPTION 'Submission identifier and demand payload are required'
            USING ERRCODE = '22023';
    END IF;

    v_customer_id := NULLIF(p_demand->>'customer_id', '')::UUID;
    IF v_customer_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles p WHERE p.id = v_customer_id
    ) THEN
        RAISE EXCEPTION 'The authenticated customer profile was not found'
            USING ERRCODE = '23503';
    END IF;

    SELECT * INTO v_saved
    FROM public.demands
    WHERE submission_id = p_submission_id;
    IF FOUND THEN
        IF v_saved.customer_id IS DISTINCT FROM v_customer_id THEN
            RAISE EXCEPTION 'Submission identifier is already in use'
                USING ERRCODE = '23505';
        END IF;
        RETURN to_jsonb(v_saved);
    END IF;

    v_quantity := NULLIF(p_demand->>'target_quantity', '')::NUMERIC;
    v_min_price := NULLIF(p_demand->>'min_target_unit_price', '')::NUMERIC;
    v_max_price := NULLIF(p_demand->>'max_target_unit_price', '')::NUMERIC;
    IF v_quantity IS NULL OR v_quantity <= 0
       OR v_min_price IS NULL OR v_min_price <= 0
       OR v_max_price IS NULL OR v_max_price < v_min_price
       OR NULLIF(btrim(p_demand->>'title'), '') IS NULL
       OR NULLIF(btrim(p_demand->>'category'), '') IS NULL
       OR NULLIF(btrim(p_demand->>'unit'), '') IS NULL
       OR COALESCE(p_demand->>'currency', '') !~ '^[A-Z]{3}$'
       OR jsonb_typeof(p_demand->'normalized_requirements') IS DISTINCT FROM 'object'
    THEN
        RAISE EXCEPTION 'Demand payload failed database validation'
            USING ERRCODE = '22023';
    END IF;

    v_normalized := p_demand->'normalized_requirements';
    FOR v_attempt IN 1..5 LOOP
        v_code := 'MT-' || upper(replace(gen_random_uuid()::text, '-', ''));
        BEGIN
            INSERT INTO public.demands (
                demand_code,
                customer_id,
                title,
                category,
                target_price,
                target_quantity,
                status,
                description,
                technical_specifications,
                dimensions,
                certifications,
                unit,
                currency,
                expected_lead_time,
                delivery_address,
                additional_requirements,
                min_target_unit_price,
                max_target_unit_price,
                submission_id,
                updated_at
            ) VALUES (
                v_code,
                v_customer_id,
                btrim(p_demand->>'title'),
                btrim(p_demand->>'category'),
                NULL,
                v_quantity,
                'Submitted'::public.demand_status,
                NULLIF(p_demand->>'description', ''),
                COALESCE(p_demand->'technical_specifications', '[]'::JSONB),
                COALESCE(p_demand->'dimensions', '{}'::JSONB),
                COALESCE(p_demand->'certifications', '[]'::JSONB),
                btrim(p_demand->>'unit'),
                upper(p_demand->>'currency'),
                NULLIF(p_demand->>'expected_lead_time', '')::INTEGER,
                COALESCE(p_demand->'delivery_address', '{}'::JSONB),
                NULLIF(p_demand->>'additional_requirements', ''),
                v_min_price,
                v_max_price,
                p_submission_id,
                now()
            )
            RETURNING * INTO v_saved;

            INSERT INTO public.demand_normalized_requirements (
                demand_id,
                extraction_version,
                product_type,
                normalized_product_name,
                normalized_category,
                normalized_material,
                normalized_specifications,
                normalized_dimensions,
                mandatory_requirements,
                optional_preferences,
                commercial_constraints,
                delivery_constraints,
                missing_information,
                clarification_questions,
                validation_errors,
                status
            ) VALUES (
                v_saved.id,
                COALESCE(NULLIF(v_normalized->>'extraction_version', ''), 'v1'),
                NULLIF(v_normalized->>'product_type', ''),
                NULLIF(v_normalized->>'normalized_product_name', ''),
                NULLIF(v_normalized->>'normalized_category', ''),
                NULLIF(v_normalized->>'normalized_material', ''),
                COALESCE(v_normalized->'normalized_specifications', '{}'::JSONB),
                COALESCE(v_normalized->'normalized_dimensions', '{}'::JSONB),
                COALESCE(v_normalized->'mandatory_requirements', '[]'::JSONB),
                COALESCE(v_normalized->'optional_preferences', '[]'::JSONB),
                COALESCE(v_normalized->'commercial_constraints', '{}'::JSONB),
                COALESCE(v_normalized->'delivery_constraints', '{}'::JSONB),
                COALESCE(v_normalized->'missing_information', '[]'::JSONB),
                COALESCE(v_normalized->'clarification_questions', '[]'::JSONB),
                COALESCE(v_normalized->'validation_errors', '[]'::JSONB),
                COALESCE(NULLIF(v_normalized->>'status', ''), 'Completed')
            );
            RETURN to_jsonb(v_saved);
        EXCEPTION WHEN unique_violation THEN
            IF EXISTS (
                SELECT 1 FROM public.demands d WHERE d.demand_code = v_code
            ) THEN
                IF v_attempt = 5 THEN
                    RAISE EXCEPTION 'Unable to allocate a unique demand reference'
                        USING ERRCODE = '23505';
                END IF;
            ELSE
                SELECT * INTO v_saved
                FROM public.demands
                WHERE submission_id = p_submission_id;
                IF FOUND AND v_saved.customer_id = v_customer_id THEN
                    RETURN to_jsonb(v_saved);
                END IF;
                RAISE;
            END IF;
        END;
    END LOOP;

    RAISE EXCEPTION 'Unable to create demand';
END;
$$;

REVOKE ALL ON FUNCTION public.create_customer_demand_v1(UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_customer_demand_v1(UUID, JSONB)
    TO service_role;

CREATE OR REPLACE FUNCTION public.update_customer_demand_v1(
    p_demand_id UUID,
    p_customer_id UUID,
    p_demand JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_saved public.demands%ROWTYPE;
    v_normalized JSONB;
    v_quantity NUMERIC;
    v_min_price NUMERIC;
    v_max_price NUMERIC;
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        RAISE EXCEPTION 'This operation requires the backend service role'
            USING ERRCODE = '42501';
    END IF;
    IF p_demand_id IS NULL OR p_customer_id IS NULL OR p_demand IS NULL THEN
        RAISE EXCEPTION 'Demand, customer, and payload are required'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_saved
    FROM public.demands
    WHERE id = p_demand_id
      AND customer_id = p_customer_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Demand not found or access denied'
            USING ERRCODE = '42501';
    END IF;
    IF v_saved.status NOT IN ('Submitted', 'Under Review') THEN
        RAISE EXCEPTION 'Demand is not eligible for modification'
            USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles p WHERE p.id = p_customer_id
    ) THEN
        RAISE EXCEPTION 'Customer profile was not found'
            USING ERRCODE = '23503';
    END IF;

    v_quantity := NULLIF(p_demand->>'target_quantity', '')::NUMERIC;
    v_min_price := NULLIF(p_demand->>'min_target_unit_price', '')::NUMERIC;
    v_max_price := NULLIF(p_demand->>'max_target_unit_price', '')::NUMERIC;
    IF v_quantity IS NULL OR v_quantity <= 0
       OR v_min_price IS NULL OR v_min_price <= 0
       OR v_max_price IS NULL OR v_max_price < v_min_price
       OR NULLIF(btrim(p_demand->>'title'), '') IS NULL
       OR NULLIF(btrim(p_demand->>'category'), '') IS NULL
       OR NULLIF(btrim(p_demand->>'unit'), '') IS NULL
       OR COALESCE(p_demand->>'currency', '') !~ '^[A-Z]{3}$'
       OR jsonb_typeof(p_demand->'normalized_requirements') IS DISTINCT FROM 'object'
    THEN
        RAISE EXCEPTION 'Demand payload failed database validation'
            USING ERRCODE = '22023';
    END IF;

    v_normalized := p_demand->'normalized_requirements';
    UPDATE public.demands
    SET title = btrim(p_demand->>'title'),
        category = btrim(p_demand->>'category'),
        description = NULLIF(p_demand->>'description', ''),
        brand = NULLIF(p_demand->>'brand', ''),
        model_number = NULLIF(p_demand->>'model_number', ''),
        technical_specifications = COALESCE(p_demand->'technical_specifications', '[]'::JSONB),
        dimensions = COALESCE(p_demand->'dimensions', '{}'::JSONB),
        certifications = COALESCE(p_demand->'certifications', '[]'::JSONB),
        target_quantity = v_quantity,
        unit = btrim(p_demand->>'unit'),
        min_target_unit_price = v_min_price,
        max_target_unit_price = v_max_price,
        currency = upper(p_demand->>'currency'),
        expected_lead_time = NULLIF(p_demand->>'expected_lead_time', '')::INTEGER,
        delivery_address = COALESCE(p_demand->'delivery_address', v_saved.delivery_address),
        additional_requirements = NULLIF(p_demand->>'additional_requirements', ''),
        updated_at = now()
    WHERE id = p_demand_id
      AND customer_id = p_customer_id
    RETURNING * INTO v_saved;

    INSERT INTO public.demand_normalized_requirements (
        demand_id,
        extraction_version,
        product_type,
        normalized_product_name,
        normalized_category,
        normalized_material,
        normalized_specifications,
        normalized_dimensions,
        mandatory_requirements,
        optional_preferences,
        commercial_constraints,
        delivery_constraints,
        missing_information,
        clarification_questions,
        validation_errors,
        status,
        updated_at
    ) VALUES (
        v_saved.id,
        COALESCE(NULLIF(v_normalized->>'extraction_version', ''), 'v1'),
        NULLIF(v_normalized->>'product_type', ''),
        NULLIF(v_normalized->>'normalized_product_name', ''),
        NULLIF(v_normalized->>'normalized_category', ''),
        NULLIF(v_normalized->>'normalized_material', ''),
        COALESCE(v_normalized->'normalized_specifications', '{}'::JSONB),
        COALESCE(v_normalized->'normalized_dimensions', '{}'::JSONB),
        COALESCE(v_normalized->'mandatory_requirements', '[]'::JSONB),
        COALESCE(v_normalized->'optional_preferences', '[]'::JSONB),
        COALESCE(v_normalized->'commercial_constraints', '{}'::JSONB),
        COALESCE(v_normalized->'delivery_constraints', '{}'::JSONB),
        COALESCE(v_normalized->'missing_information', '[]'::JSONB),
        COALESCE(v_normalized->'clarification_questions', '[]'::JSONB),
        COALESCE(v_normalized->'validation_errors', '[]'::JSONB),
        COALESCE(NULLIF(v_normalized->>'status', ''), 'Completed'),
        now()
    )
    ON CONFLICT (demand_id, extraction_version) DO UPDATE
    SET product_type = EXCLUDED.product_type,
        normalized_product_name = EXCLUDED.normalized_product_name,
        normalized_category = EXCLUDED.normalized_category,
        normalized_material = EXCLUDED.normalized_material,
        normalized_specifications = EXCLUDED.normalized_specifications,
        normalized_dimensions = EXCLUDED.normalized_dimensions,
        mandatory_requirements = EXCLUDED.mandatory_requirements,
        optional_preferences = EXCLUDED.optional_preferences,
        commercial_constraints = EXCLUDED.commercial_constraints,
        delivery_constraints = EXCLUDED.delivery_constraints,
        missing_information = EXCLUDED.missing_information,
        clarification_questions = EXCLUDED.clarification_questions,
        validation_errors = EXCLUDED.validation_errors,
        status = EXCLUDED.status,
        updated_at = now();

    RETURN to_jsonb(v_saved);
END;
$$;

REVOKE ALL ON FUNCTION public.update_customer_demand_v1(UUID, UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_customer_demand_v1(UUID, UUID, JSONB)
    TO service_role;

NOTIFY pgrst, 'reload schema';
