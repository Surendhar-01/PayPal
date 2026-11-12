-- Read-only preflight for 020_merchant_offers_group_id_draft.sql.
-- Run only against the intended database with an authorized SQL inspection role.
-- Every executable statement is SELECT-only. This is not a migration.
-- Optional merchant_offers.group_id is read through to_jsonb(row), so data checks
-- remain valid before that column exists.

-- 1. Offer counts and the migration's backfill/duplicate conflict conditions.
-- backfill_candidates matches 020's UPDATE predicate.
-- offers_without_demand_group counts linked demands whose group_id is NULL.
-- The duplicate grouping matches 020's prospective unique-index preflight.
WITH offer_state AS (
    SELECT
        offer.id AS offer_id,
        offer.demand_id,
        offer.merchant_id,
        to_jsonb(offer)->>'group_id' AS current_offer_group_id,
        demand.id AS matched_demand_id,
        to_jsonb(demand)->>'group_id' AS linked_demand_group_id
    FROM public.merchant_offers AS offer
    LEFT JOIN public.demands AS demand
      ON demand.id = offer.demand_id
), duplicate_keys AS (
    SELECT
        COALESCE(current_offer_group_id, linked_demand_group_id) AS prospective_group_id,
        merchant_id,
        count(*) AS offer_count
    FROM offer_state
    WHERE COALESCE(current_offer_group_id, linked_demand_group_id) IS NOT NULL
      AND merchant_id IS NOT NULL
    GROUP BY COALESCE(current_offer_group_id, linked_demand_group_id), merchant_id
    HAVING count(*) > 1
), group_reference_orphans AS (
    SELECT count(*) AS orphaned_group_reference_count
    FROM offer_state
    LEFT JOIN public.demand_groups AS demand_group
      ON demand_group.id::TEXT = COALESCE(
          current_offer_group_id,
          linked_demand_group_id
      )
    WHERE COALESCE(current_offer_group_id, linked_demand_group_id) IS NOT NULL
      AND demand_group.id IS NULL
)
SELECT
    (SELECT count(*) FROM offer_state) AS total_merchant_offers,
    (SELECT count(*) FROM offer_state
     WHERE matched_demand_id IS NOT NULL
       AND current_offer_group_id IS NULL
       AND linked_demand_group_id IS NOT NULL) AS backfill_candidates,
    (SELECT count(*) FROM offer_state
     WHERE matched_demand_id IS NOT NULL
       AND linked_demand_group_id IS NULL) AS offers_without_demand_group,
    (SELECT count(*) FROM offer_state
     WHERE demand_id IS NOT NULL
       AND matched_demand_id IS NULL) AS offers_with_orphaned_demand_reference,
    (SELECT count(*) FROM duplicate_keys) AS duplicate_group_merchant_key_count,
    (SELECT COALESCE(sum(offer_count), 0) FROM duplicate_keys) AS offers_in_duplicate_keys,
    (SELECT orphaned_group_reference_count FROM group_reference_orphans)
        AS offers_with_orphaned_group_reference,
    (SELECT count(*) FROM offer_state
     WHERE matched_demand_id IS NOT NULL
       AND current_offer_group_id IS NOT NULL
       AND current_offer_group_id IS DISTINCT FROM linked_demand_group_id)
        AS existing_offer_demand_group_mismatches;

-- 2. Optional merchant_offers.group_id column contract.
-- A missing column returns exists = false and NULL type/nullability, not an error.
SELECT
    attribute.attname IS NOT NULL AS group_id_column_exists,
    CASE WHEN attribute.attname IS NULL THEN NULL
         ELSE format_type(attribute.atttypid, attribute.atttypmod)
    END AS column_type,
    CASE WHEN attribute.attname IS NULL THEN NULL
         ELSE NOT attribute.attnotnull
    END AS is_nullable
FROM (VALUES (to_regclass('public.merchant_offers'))) AS target(relation_oid)
LEFT JOIN pg_attribute AS attribute
  ON attribute.attrelid = target.relation_oid
 AND attribute.attname = 'group_id'
 AND attribute.attnum > 0
 AND NOT attribute.attisdropped;

-- 3. Foreign keys involving merchant_offers.group_id, if any.
SELECT
    constraint_info.conname AS constraint_name,
    pg_get_constraintdef(constraint_info.oid, TRUE) AS definition,
    constraint_info.convalidated AS is_validated
FROM pg_constraint AS constraint_info
WHERE constraint_info.contype = 'f'
  AND (
      constraint_info.conrelid = to_regclass('public.merchant_offers')
      OR constraint_info.confrelid = to_regclass('public.merchant_offers')
  )
  AND pg_get_constraintdef(constraint_info.oid, TRUE) ILIKE '%group_id%'
ORDER BY constraint_info.conname;

-- 4. Indexes involving merchant_offers.group_id, if any.
SELECT
    index_class.relname AS index_name,
    pg_get_indexdef(index_info.indexrelid) AS definition,
    index_info.indisunique AS is_unique,
    index_info.indisvalid AS is_valid,
    index_info.indisready AS is_ready
FROM pg_index AS index_info
JOIN pg_class AS index_class
  ON index_class.oid = index_info.indexrelid
WHERE index_info.indrelid = to_regclass('public.merchant_offers')
  AND pg_get_indexdef(index_info.indexrelid) ILIKE '%group_id%'
ORDER BY index_class.relname;

-- 5. RLS status. relrowsecurity = false means policies are not enforced for ordinary roles.
SELECT
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS rls_forced
FROM (VALUES (to_regclass('public.merchant_offers'))) AS target(relation_oid)
LEFT JOIN pg_class AS relation
  ON relation.oid = target.relation_oid;

-- 6. Every existing policy, including policy command, roles, USING, and WITH CHECK.
SELECT
    policyname,
    permissive,
    roles,
    cmd,
    qual AS using_expression,
    with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'merchant_offers'
ORDER BY policyname;

-- 7. Compare the three policies replaced by 020 to stable migration 001 definitions.
-- The offers_delete row is included because 020 leaves that stable policy in place.
-- Expression comparison ignores case, whitespace, and redundant parentheses.
WITH expected_policies AS (
    SELECT *
    FROM (VALUES
        (
            'offers_select'::TEXT,
            'SELECT'::TEXT,
            '(merchant_id = auth.uid()) OR EXISTS '
                || '(SELECT 1 FROM public.demands d WHERE d.id = merchant_offers.demand_id '
                || 'AND d.customer_id = auth.uid())',
            NULL::TEXT
        ),
        (
            'offers_insert'::TEXT,
            'INSERT'::TEXT,
            NULL::TEXT,
            '(merchant_id = auth.uid())'
        ),
        (
            'offers_update'::TEXT,
            'UPDATE'::TEXT,
            '(merchant_id = auth.uid())',
            '(merchant_id = auth.uid())'
        ),
        (
            'offers_delete'::TEXT,
            'DELETE'::TEXT,
            '(merchant_id = auth.uid())',
            NULL::TEXT
        )
    ) AS expected(policyname, expected_command, expected_using, expected_check)
), comparison AS (
    SELECT
        expected.policyname,
        actual.policyname IS NOT NULL AS policy_exists,
        COALESCE(actual.permissive = 'PERMISSIVE', FALSE) AS is_permissive,
        COALESCE(actual.cmd = expected.expected_command, FALSE) AS command_matches,
        COALESCE(actual.roles::TEXT = '{public}', FALSE) AS roles_match_public,
        COALESCE(
            regexp_replace(lower(COALESCE(actual.qual, '')), '[[:space:]()]', '', 'g')
            = regexp_replace(lower(COALESCE(expected.expected_using, '')), '[[:space:]()]', '', 'g'),
            FALSE
        ) AS using_matches,
        CASE
            WHEN expected.expected_check IS NULL THEN actual.with_check IS NULL
            ELSE COALESCE(
                regexp_replace(
                    lower(COALESCE(actual.with_check, actual.qual, '')),
                    '[[:space:]()]', '', 'g'
                )
                = regexp_replace(lower(expected.expected_check), '[[:space:]()]', '', 'g'),
                FALSE
            )
        END AS with_check_matches
    FROM expected_policies AS expected
    LEFT JOIN pg_policies AS actual
      ON actual.schemaname = 'public'
     AND actual.tablename = 'merchant_offers'
     AND actual.policyname = expected.policyname
)
SELECT
    policyname,
    policy_exists,
    is_permissive,
    command_matches,
    roles_match_public,
    using_matches,
    with_check_matches,
    policy_exists
        AND is_permissive
        AND command_matches
        AND roles_match_public
        AND using_matches
        AND with_check_matches AS matches_stable_definition
FROM comparison
ORDER BY policyname;

-- 8. Unexpected permissive policies are listed for manual review.
-- PostgreSQL combines permissive policies with OR, so an extra policy can widen access.
SELECT
    policyname,
    cmd,
    roles,
    qual AS using_expression,
    with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'merchant_offers'
  AND permissive = 'PERMISSIVE'
  AND policyname NOT IN (
      'offers_select',
      'offers_insert',
      'offers_update',
      'offers_delete'
  )
ORDER BY policyname;