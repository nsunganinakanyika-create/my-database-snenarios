

DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;
DROP PROCEDURE IF EXISTS reserve_workstations(INTEGER, VARCHAR, INTEGER);
DROP PROCEDURE IF EXISTS cancel_reservation(INTEGER);

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    session_name VARCHAR(100) NOT NULL,
    available_workstations INTEGER NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL REFERENCES lab_sessions(session_id),
    lecturer VARCHAR(100) NOT NULL,
    workstations INTEGER NOT NULL,
    reservation_status VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
        CHECK (reservation_status IN ('RESERVED', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
('Database Practical', 20),
('Networking Practical', 10),
('Programming Practical', 15);

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    seats INTEGER;
BEGIN
    SELECT available_workstations INTO seats
    FROM lab_sessions WHERE session_id = 2;

    IF seats = 0 THEN
        RAISE NOTICE 'Networking Practical: full.';
    ELSIF seats <= 3 THEN
        RAISE NOTICE 'Networking Practical: nearly full (% workstations left).', seats;
    ELSE
        RAISE NOTICE 'Networking Practical: enough workstations (% available).', seats;
    END IF;
END $$;

-- 3. WHILE and numeric FOR
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- 4. Reserve procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INTEGER,
    p_lecturer VARCHAR,
    p_workstations INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: must be greater than zero.';
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session ID % does not exist.', p_session_id;
    END IF;

    IF p_workstations > v_available THEN
        RAISE EXCEPTION 'Not enough workstations. Requested %, available %.',
            p_workstations, v_available;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_workstations
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, reservation_status)
    VALUES (p_session_id, p_lecturer, p_workstations, 'RESERVED');

    RAISE NOTICE 'Reservation recorded successfully.';
END $$;

-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 5);
CALL reserve_workstations(2, 'Dr. Phiri', 4);

DO $$
BEGIN
    BEGIN
        CALL reserve_workstations(2, 'Dr. Tembo', 10);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Expected failed reservation: %', SQLERRM;
    END;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. Cancel procedure; second call must not release again
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INTEGER;
    v_workstations INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT session_id, workstations, reservation_status
    INTO v_session_id, v_workstations, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation ID % does not exist.', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. Workstations will not be released again.',
            p_reservation_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_workstations
    WHERE session_id = v_session_id;

    UPDATE reservations
    SET reservation_status = 'CANCELLED'
    WHERE reservation_id = p_reservation_id;

    RAISE NOTICE 'Reservation % cancelled successfully.', p_reservation_id;
END $$;

CALL cancel_reservation(1);
CALL cancel_reservation(1);

-- 7. Explicit cursor for sessions with few workstations
DO $$
DECLARE
    session_cursor CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 5;
    rec RECORD;
BEGIN
    OPEN session_cursor;
    LOOP
        FETCH session_cursor INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations: ID %, %, % remaining.',
            rec.session_id, rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE session_cursor;
END $$;

-- 8. Zero workstation request handled by EXCEPTION
DO $$
BEGIN
    BEGIN
        CALL reserve_workstations(1, 'Dr. Invalid', 0);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Invalid zero-workstation request handled: %', SQLERRM;
    END;
END $$;

-- 9. Final results
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
