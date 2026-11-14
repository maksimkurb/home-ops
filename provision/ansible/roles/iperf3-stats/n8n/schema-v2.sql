-- iperf3-stats schema v2 for the `lab` database (Grafana datasource "PostgreSQL Lab").
--
-- Adds:
--   * iperf_logs: test_type, run_id, omit/duration, sender/receiver Mbps and a
--     generated peer_host_id ("the other end" from the client's point of view),
--     so A <-> B panels no longer need CASE expressions on source/target.
--   * iperf_traces / iperf_trace_hops / iperf_trace_responders: ttl traceroutes
--     (ICMP "path" pass for loss/latency/jitter, multi-flow "ecmp" pass).
--   * iperf_ingest(jsonb): one atomic, idempotent ingest call for the n8n workflow
--     (replaces the three "Fetch host" nodes + "Insert result").
--   * iperf_prune(): retention, called daily by the workflow.
--
-- Idempotent: safe to re-run. Apply BEFORE importing the v3 workflow and BEFORE
-- deploying the new client script (it sends test_type=trace payloads).
--
--   kubectl -n database exec -i homelab-pgsql-0 -c postgres -- \
--     psql -U postgres -d lab -v ON_ERROR_STOP=1 < schema-v2.sql

BEGIN;

-- ---------------------------------------------------------------------------
-- Hosts
-- ---------------------------------------------------------------------------

-- Race-free get-or-create (the old CTE insert failed on concurrent first sightings).
CREATE OR REPLACE FUNCTION iperf_host_id(p_host text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_id bigint;
BEGIN
    IF p_host IS NULL OR btrim(p_host) = '' THEN
        RAISE EXCEPTION 'iperf_host_id: empty host name';
    END IF;
    SELECT id INTO v_id FROM iperf_hosts WHERE host = p_host;
    IF v_id IS NULL THEN
        INSERT INTO iperf_hosts (host) VALUES (p_host)
        ON CONFLICT (host) DO NOTHING
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            SELECT id INTO v_id FROM iperf_hosts WHERE host = p_host;
        END IF;
    END IF;
    RETURN v_id;
END;
$$;

-- The clients targeted "charilie.node.kurb.me" (NXDOMAIN) since 2026-10-19.
-- Rename the host row so VPS-C history and alias carry over to the fixed name.
UPDATE iperf_hosts h
SET host = 'charlie.node.kurb.me'
WHERE h.host = 'charilie.node.kurb.me'
  AND NOT EXISTS (SELECT 1 FROM iperf_hosts WHERE host = 'charlie.node.kurb.me');

-- ---------------------------------------------------------------------------
-- Bandwidth / ping results
-- ---------------------------------------------------------------------------

ALTER TABLE iperf_logs
    ADD COLUMN IF NOT EXISTS test_type      text,
    ADD COLUMN IF NOT EXISTS run_id         uuid,
    ADD COLUMN IF NOT EXISTS schema_version smallint,
    ADD COLUMN IF NOT EXISTS omit_sec       smallint,
    ADD COLUMN IF NOT EXISTS duration_sec   smallint,
    ADD COLUMN IF NOT EXISTS streams        smallint,
    ADD COLUMN IF NOT EXISTS sender_mbps    numeric(10, 4),
    ADD COLUMN IF NOT EXISTS receiver_mbps  numeric(10, 4),
    ADD COLUMN IF NOT EXISTS peer_host_id   bigint
        GENERATED ALWAYS AS (
            CASE WHEN source_host_id = run_on_host_id THEN target_host_id ELSE source_host_id END
        ) STORED;

-- Backfill: v1 rows only carried the direction implicitly.
UPDATE iperf_logs
SET test_type = CASE
        WHEN jsonb_array_length(second_measurements -> 'data') = 0 THEN 'icmp'
        WHEN source_host_id = run_on_host_id THEN 'upload'
        ELSE 'download'
    END
WHERE test_type IS NULL;

ALTER TABLE iperf_logs ALTER COLUMN test_type SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'iperf_logs_test_type_check') THEN
        ALTER TABLE iperf_logs ADD CONSTRAINT iperf_logs_test_type_check
            CHECK (test_type IN ('download', 'upload', 'icmp'));
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS iperf_logs_pair_time_idx
    ON iperf_logs (run_on_host_id, peer_host_id, test_type, created_at DESC);
CREATE INDEX IF NOT EXISTS iperf_logs_created_at_idx ON iperf_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS iperf_logs_run_id_idx ON iperf_logs (run_id) WHERE run_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Traceroutes (ttl)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS iperf_traces (
    id              bigserial PRIMARY KEY,
    created_at      timestamptz NOT NULL DEFAULT now(),
    started_at      timestamptz,
    run_id          uuid,
    idempotency_key text NOT NULL,
    run_on_host_id  bigint NOT NULL REFERENCES iperf_hosts ON DELETE RESTRICT,
    peer_host_id    bigint NOT NULL REFERENCES iperf_hosts ON DELETE RESTRICT,
    bind_interface  varchar(64),
    target_ip       inet,
    source_ip       inet,
    gateway_ip      inet,

    -- From the ICMP "path" pass
    reached         boolean,
    hop_count       smallint,
    dest_loss_pct   numeric(5, 2),
    dest_min_ms     numeric(10, 3),
    dest_avg_ms     numeric(10, 3),
    dest_max_ms     numeric(10, 3),
    dest_stddev_ms  numeric(10, 3),
    dest_jitter_ms  numeric(10, 3),
    -- worst intermediate-hop loss that persists to every later hop (= real loss
    -- that starts at that hop, as opposed to ICMP rate limiting on a router)
    loss_origin_ttl smallint,
    path_signature  text,   -- primary responder per TTL, '*' for silent hops
    path_hash       text,   -- md5(path_signature), cheap "did the route change" key
    asn_path        text,   -- collapsed AS numbers along the path, e.g. "21299 13335"

    -- From the multi-flow "ecmp" pass
    ecmp_protocol   text,
    ecmp_flows      smallint,
    ecmp_hops       smallint,  -- hops answered by more than one router
    ecmp_max_width  smallint,  -- most routers seen at a single hop

    raw             jsonb,     -- compacted ttl output; nulled by iperf_prune()

    UNIQUE (idempotency_key, run_on_host_id, peer_host_id)
);

CREATE INDEX IF NOT EXISTS iperf_traces_pair_time_idx
    ON iperf_traces (run_on_host_id, peer_host_id, created_at DESC);
CREATE INDEX IF NOT EXISTS iperf_traces_created_at_idx ON iperf_traces (created_at DESC);

CREATE TABLE IF NOT EXISTS iperf_trace_hops (
    trace_id     bigint   NOT NULL REFERENCES iperf_traces ON DELETE CASCADE,
    pass         text     NOT NULL CHECK (pass IN ('path', 'ecmp')),
    ttl          smallint NOT NULL,
    sent         integer  NOT NULL,
    received     integer  NOT NULL,
    timeouts     integer  NOT NULL,
    loss_pct     numeric(5, 2),
    primary_ip   inet,
    responders   smallint NOT NULL,
    rate_limited boolean,
    PRIMARY KEY (trace_id, pass, ttl)
);

CREATE TABLE IF NOT EXISTS iperf_trace_responders (
    trace_id      bigint   NOT NULL,
    pass          text     NOT NULL,
    ttl           smallint NOT NULL,
    ip            inet     NOT NULL,
    hostname      text,
    asn           integer,
    asn_name      text,
    asn_prefix    text,
    received      integer  NOT NULL,
    share_pct     numeric(5, 2),   -- share of this hop's replies
    min_ms        numeric(10, 3),
    avg_ms        numeric(10, 3),
    max_ms        numeric(10, 3),
    stddev_ms     numeric(10, 3),
    jitter_ms     numeric(10, 3),  -- mean |RTT(n) - RTT(n-1)|
    jitter_max_ms numeric(10, 3),
    flows         smallint[],      -- ECMP flow ids this router answered
    mpls_labels   jsonb,
    PRIMARY KEY (trace_id, pass, ttl, ip),
    FOREIGN KEY (trace_id, pass, ttl)
        REFERENCES iperf_trace_hops (trace_id, pass, ttl) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS iperf_trace_responders_ip_idx ON iperf_trace_responders (ip);

-- ---------------------------------------------------------------------------
-- Ingest
-- ---------------------------------------------------------------------------

-- p_in: {"idempotency_key": "...", "payload": <webhook body>}
-- Returns {"kind": "...", "id": ..., "duplicate": bool}.
CREATE OR REPLACE FUNCTION iperf_ingest(p_in jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    p             jsonb := p_in -> 'payload';
    v_key         text  := p_in ->> 'idempotency_key';
    v_version     smallint;
    v_type        text;
    v_source_id   bigint;
    v_target_id   bigint;
    v_run_on_id   bigint;
    v_peer_id     bigint;
    v_speeds      jsonb;
    v_avg         numeric;
    v_id          bigint;
    v_path        jsonb;
    v_ecmp        jsonb;
    v_summary     jsonb;
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
        RAISE EXCEPTION 'iperf_ingest: payload must be a JSON object';
    END IF;
    IF v_key IS NULL OR v_key = '' THEN
        RAISE EXCEPTION 'iperf_ingest: idempotency_key is required';
    END IF;

    v_version   := NULLIF(p ->> 'schema_version', '')::smallint;
    v_run_on_id := iperf_host_id(p ->> 'iperf_run_on_hostname');
    v_source_id := iperf_host_id(p ->> 'source_hostname');
    v_target_id := iperf_host_id(p ->> 'target_hostname');
    v_peer_id   := CASE WHEN v_source_id = v_run_on_id THEN v_target_id ELSE v_source_id END;

    v_type := p ->> 'test_type';
    IF v_type IS NULL OR v_type NOT IN ('download', 'upload', 'icmp', 'trace') THEN
        -- v1 clients: direction is implied by who sent the data
        v_type := CASE
            WHEN jsonb_array_length(COALESCE(p -> 'intervals', '[]')) = 0 THEN 'icmp'
            WHEN v_source_id = v_run_on_id THEN 'upload'
            ELSE 'download'
        END;
    END IF;

    -- ---------------------------------------------------------------- trace
    IF v_type = 'trace' THEN
        v_path := NULLIF(p -> 'trace' -> 'path', 'null');
        v_ecmp := NULLIF(p -> 'trace' -> 'ecmp', 'null');

        WITH hops AS (
            SELECT (h ->> 'ttl')::int AS ttl,
                   (h ->> 'received')::int AS received,
                   (h ->> 'timeouts')::int AS timeouts,
                   h ->> 'primary' AS primary_ip,
                   h -> 'responders' -> (h ->> 'primary') AS pr
            FROM jsonb_array_elements(COALESCE(v_path -> 'hops', '[]')) h
        ), loss AS (
            SELECT ttl, primary_ip, pr,
                   CASE WHEN received + timeouts > 0
                        THEN 100.0 * timeouts / (received + timeouts) END AS loss_pct
            FROM hops
        ), dest AS (
            SELECT * FROM loss ORDER BY ttl DESC LIMIT 1
        ), origin AS (
            -- first TTL from which every later responding hop loses >= 5 %
            SELECT min(l.ttl) AS ttl
            FROM loss l
            WHERE l.primary_ip IS NOT NULL
              AND l.loss_pct >= 5
              AND NOT EXISTS (
                  SELECT 1 FROM loss l2
                  WHERE l2.ttl > l.ttl AND l2.primary_ip IS NOT NULL AND l2.loss_pct < 5
              )
        ), asns AS (
            SELECT ttl, (pr -> 'asn' ->> 'number')::int AS asn,
                   lag((pr -> 'asn' ->> 'number')::int) OVER (ORDER BY ttl) AS prev_asn
            FROM (
                SELECT ttl, pr FROM hops WHERE pr -> 'asn' ->> 'number' IS NOT NULL
            ) s
        ), ecmp AS (
            SELECT count(*) FILTER (WHERE n > 1) AS ecmp_hops, max(n) AS width
            FROM (
                SELECT (SELECT count(*) FROM jsonb_object_keys(COALESCE(h -> 'responders', '{}'))) AS n
                FROM jsonb_array_elements(COALESCE(v_ecmp -> 'hops', '[]')) h
            ) s
        )
        SELECT jsonb_build_object(
            'reached', COALESCE((v_path ->> 'complete')::boolean, false)
                       OR COALESCE((SELECT primary_ip FROM dest) = v_path -> 'target' ->> 'resolved', false),
            'hop_count', COALESCE((v_path ->> 'dest_ttl')::int, (SELECT ttl FROM dest)),
            'dest_loss_pct', (SELECT round(loss_pct, 2) FROM dest),
            'dest_min_ms', (SELECT round((pr ->> 'min_rtt')::numeric / 1000, 3) FROM dest),
            'dest_avg_ms', (SELECT round((pr ->> 'mean_rtt')::numeric / 1000, 3) FROM dest),
            'dest_max_ms', (SELECT round((pr ->> 'max_rtt')::numeric / 1000, 3) FROM dest),
            'dest_stddev_ms', (SELECT CASE WHEN (pr ->> 'received')::int > 1
                                   THEN round((sqrt((pr ->> 'm2')::numeric / ((pr ->> 'received')::int - 1)) / 1000)::numeric, 3)
                               END FROM dest),
            'dest_jitter_ms', (SELECT round((pr ->> 'jitter_avg')::numeric / 1000, 3) FROM dest),
            'loss_origin_ttl', (SELECT ttl FROM origin),
            'path_signature', (SELECT string_agg(COALESCE(primary_ip, '*'), ' ' ORDER BY ttl) FROM hops),
            'asn_path', (SELECT string_agg(asn::text, ' ' ORDER BY ttl) FROM asns
                         WHERE prev_asn IS DISTINCT FROM asn),
            'ecmp_hops', (SELECT ecmp_hops FROM ecmp),
            'ecmp_max_width', (SELECT width FROM ecmp)
        ) INTO v_summary;

        INSERT INTO iperf_traces (
            started_at, run_id, idempotency_key, run_on_host_id, peer_host_id, bind_interface,
            target_ip, source_ip, gateway_ip,
            reached, hop_count, dest_loss_pct, dest_min_ms, dest_avg_ms, dest_max_ms,
            dest_stddev_ms, dest_jitter_ms, loss_origin_ttl, path_signature, path_hash, asn_path,
            ecmp_protocol, ecmp_flows, ecmp_hops, ecmp_max_width, raw
        ) VALUES (
            COALESCE(v_path ->> 'started_at', v_ecmp ->> 'started_at')::timestamptz,
            NULLIF(p ->> 'run_id', '')::uuid, v_key, v_run_on_id, v_peer_id, p ->> 'bind_interface',
            (COALESCE(v_path, v_ecmp) -> 'target' ->> 'resolved')::inet,
            (COALESCE(v_path, v_ecmp) ->> 'source_ip')::inet,
            (COALESCE(v_path, v_ecmp) ->> 'gateway')::inet,
            CASE WHEN v_path IS NOT NULL THEN (v_summary ->> 'reached')::boolean END,
            (v_summary ->> 'hop_count')::smallint,
            (v_summary ->> 'dest_loss_pct')::numeric,
            (v_summary ->> 'dest_min_ms')::numeric,
            (v_summary ->> 'dest_avg_ms')::numeric,
            (v_summary ->> 'dest_max_ms')::numeric,
            (v_summary ->> 'dest_stddev_ms')::numeric,
            (v_summary ->> 'dest_jitter_ms')::numeric,
            (v_summary ->> 'loss_origin_ttl')::smallint,
            v_summary ->> 'path_signature',
            md5(v_summary ->> 'path_signature'),
            v_summary ->> 'asn_path',
            lower(v_ecmp -> 'config' ->> 'protocol'),
            (v_ecmp -> 'config' ->> 'flows')::smallint,
            (v_summary ->> 'ecmp_hops')::smallint,
            (v_summary ->> 'ecmp_max_width')::smallint,
            p -> 'trace'
        )
        ON CONFLICT (idempotency_key, run_on_host_id, peer_host_id) DO NOTHING
        RETURNING id INTO v_id;

        IF v_id IS NULL THEN
            SELECT id INTO v_id FROM iperf_traces
            WHERE idempotency_key = v_key AND run_on_host_id = v_run_on_id AND peer_host_id = v_peer_id;
            RETURN jsonb_build_object('kind', 'trace', 'id', v_id, 'duplicate', true);
        END IF;

        INSERT INTO iperf_trace_hops (trace_id, pass, ttl, sent, received, timeouts, loss_pct,
                                      primary_ip, responders, rate_limited)
        SELECT v_id, passes.pass, (h ->> 'ttl')::smallint,
               (h ->> 'sent')::int, (h ->> 'received')::int, (h ->> 'timeouts')::int,
               CASE WHEN (h ->> 'received')::int + (h ->> 'timeouts')::int > 0
                    THEN round(100.0 * (h ->> 'timeouts')::int
                               / ((h ->> 'received')::int + (h ->> 'timeouts')::int), 2) END,
               (h ->> 'primary')::inet,
               (SELECT count(*) FROM jsonb_object_keys(COALESCE(h -> 'responders', '{}'))),
               (h -> 'rate_limit' ->> 'suspected')::boolean
        FROM (VALUES ('path', v_path), ('ecmp', v_ecmp)) AS passes(pass, session)
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(passes.session -> 'hops', '[]')) h;

        INSERT INTO iperf_trace_responders (trace_id, pass, ttl, ip, hostname, asn, asn_name, asn_prefix,
                                            received, share_pct, min_ms, avg_ms, max_ms, stddev_ms,
                                            jitter_ms, jitter_max_ms, flows, mpls_labels)
        SELECT v_id, passes.pass, (h ->> 'ttl')::smallint, r.key::inet,
               r.value ->> 'hostname',
               (r.value -> 'asn' ->> 'number')::int,
               r.value -> 'asn' ->> 'name',
               r.value -> 'asn' ->> 'prefix',
               (r.value ->> 'received')::int,
               CASE WHEN (h ->> 'received')::int > 0
                    THEN round(100.0 * (r.value ->> 'received')::int / (h ->> 'received')::int, 2) END,
               round((r.value ->> 'min_rtt')::numeric / 1000, 3),
               round((r.value ->> 'mean_rtt')::numeric / 1000, 3),
               round((r.value ->> 'max_rtt')::numeric / 1000, 3),
               CASE WHEN (r.value ->> 'received')::int > 1
                    THEN round((sqrt((r.value ->> 'm2')::numeric / ((r.value ->> 'received')::int - 1)) / 1000)::numeric, 3) END,
               round((r.value ->> 'jitter_avg')::numeric / 1000, 3),
               round((r.value ->> 'jitter_max')::numeric / 1000, 3),
               (SELECT array_agg(f.key::smallint ORDER BY f.key::int)
                FROM jsonb_each(COALESCE(h -> 'flow_paths', '{}')) f
                WHERE f.value -> 'responder_counts' ? r.key),
               NULLIF(r.value -> 'mpls_labels', 'null')
        FROM (VALUES ('path', v_path), ('ecmp', v_ecmp)) AS passes(pass, session)
        CROSS JOIN LATERAL jsonb_array_elements(COALESCE(passes.session -> 'hops', '[]')) h
        CROSS JOIN LATERAL jsonb_each(COALESCE(h -> 'responders', '{}')) r;

        RETURN jsonb_build_object('kind', 'trace', 'id', v_id, 'duplicate', false);
    END IF;

    -- ------------------------------------------------- download / upload / icmp
    -- Per-second Mbps, without the --omit slow-start intervals
    SELECT COALESCE(jsonb_agg(round((i -> 'sum' ->> 'bits_per_second')::numeric / 1e6, 2) ORDER BY ord), '[]')
    INTO v_speeds
    FROM jsonb_array_elements(COALESCE(p -> 'intervals', '[]')) WITH ORDINALITY AS t(i, ord)
    WHERE i -> 'sum' IS NOT NULL
      AND NOT COALESCE((i -> 'sum' ->> 'omitted')::boolean, false);

    IF v_type = 'icmp' THEN
        v_avg := 0;
    ELSIF v_version >= 2 THEN
        -- Receiver-side total over the measured window
        v_avg := round((p -> 'end' -> 'sum_received' ->> 'bits_per_second')::numeric / 1e6, 4);
    ELSE
        -- v1: mean of the per-second samples after dropping the first 30 %
        SELECT COALESCE(avg(s::numeric), 0) INTO v_avg
        FROM jsonb_array_elements_text(v_speeds) WITH ORDINALITY AS t(s, ord)
        WHERE ord > ceil(jsonb_array_length(v_speeds) * 0.3);
    END IF;

    INSERT INTO iperf_logs (
        average_speed, source_host_id, target_host_id, run_on_host_id, idempotency_key,
        second_measurements, latency_idle, latency_loaded, retransmits, bind_interface,
        test_type, run_id, schema_version, omit_sec, duration_sec, streams, sender_mbps, receiver_mbps
    ) VALUES (
        COALESCE(v_avg, 0), v_source_id, v_target_id, v_run_on_id, v_key,
        jsonb_build_object('data', v_speeds),
        NULLIF(p -> 'latency_idle', 'null'),
        NULLIF(p -> 'latency_loaded', 'null'),
        (p -> 'end' -> 'sum_sent' ->> 'retransmits')::int,
        p ->> 'bind_interface',
        v_type,
        NULLIF(p ->> 'run_id', '')::uuid,
        v_version,
        (p ->> 'omit_sec')::smallint,
        COALESCE((p ->> 'duration_sec')::smallint, (p -> 'start' -> 'test_start' ->> 'duration')::smallint),
        (p -> 'start' -> 'test_start' ->> 'num_streams')::smallint,
        round((p -> 'end' -> 'sum_sent' ->> 'bits_per_second')::numeric / 1e6, 4),
        round((p -> 'end' -> 'sum_received' ->> 'bits_per_second')::numeric / 1e6, 4)
    )
    ON CONFLICT (idempotency_key, run_on_host_id, target_host_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM iperf_logs
        WHERE idempotency_key = v_key AND run_on_host_id = v_run_on_id AND target_host_id = v_target_id;
        RETURN jsonb_build_object('kind', v_type, 'id', v_id, 'duplicate', true);
    END IF;
    RETURN jsonb_build_object('kind', v_type, 'id', v_id, 'duplicate', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

-- ~1.6k traces/day at the current schedule; per-hop rows are ~25x that.
CREATE OR REPLACE FUNCTION iperf_prune(
    p_raw_days  integer DEFAULT 14,   -- keep compacted ttl JSON for drill-down
    p_hops_days integer DEFAULT 180   -- keep per-hop/per-router rows
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_raw  bigint;
    v_hops bigint;
BEGIN
    UPDATE iperf_traces SET raw = NULL
    WHERE raw IS NOT NULL AND created_at < now() - make_interval(days => p_raw_days);
    GET DIAGNOSTICS v_raw = ROW_COUNT;

    DELETE FROM iperf_trace_hops th
    USING iperf_traces t
    WHERE t.id = th.trace_id AND t.created_at < now() - make_interval(days => p_hops_days);
    GET DIAGNOSTICS v_hops = ROW_COUNT;

    RETURN jsonb_build_object('raw_cleared', v_raw, 'hops_deleted', v_hops);
END;
$$;

-- Grafana reads with the datasource user; n8n writes with the "lab" user.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON iperf_traces, iperf_trace_hops, iperf_trace_responders TO lab;
        GRANT USAGE ON SEQUENCE iperf_traces_id_seq TO lab;
        ALTER TABLE iperf_traces OWNER TO lab;
        ALTER TABLE iperf_trace_hops OWNER TO lab;
        ALTER TABLE iperf_trace_responders OWNER TO lab;
        ALTER FUNCTION iperf_host_id(text) OWNER TO lab;
        ALTER FUNCTION iperf_ingest(jsonb) OWNER TO lab;
        ALTER FUNCTION iperf_prune(integer, integer) OWNER TO lab;
    END IF;
END;
$$;

COMMIT;
