-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 3: Student Hostel Room Allocation
-- Replace STUDENT_NUMBER in the filename with your student number before submission.

DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;
DROP PROCEDURE IF EXISTS allocate_room(INTEGER, VARCHAR);
DROP PROCEDURE IF EXISTS check_out(INTEGER);

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_name VARCHAR(50) NOT NULL,
    available_bed_spaces INTEGER NOT NULL CHECK (available_bed_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_number VARCHAR(30) NOT NULL,
    room_id INTEGER NOT NULL REFERENCES hostel_rooms(room_id),
    allocation_status VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
        CHECK (allocation_status IN ('ALLOCATED', 'COMPLETED'))
);

INSERT INTO hostel_rooms (room_name, available_bed_spaces) VALUES
('Block A - Room 101', 3),
('Block A - Room 102', 1),
('Block B - Room 201', 2);

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    spaces INTEGER;
BEGIN
    SELECT available_bed_spaces INTO spaces
    FROM hostel_rooms WHERE room_id = 2;

    IF spaces = 0 THEN
        RAISE NOTICE 'Room 102: full.';
    ELSIF spaces = 1 THEN
        RAISE NOTICE 'Room 102: one space left.';
    ELSE
        RAISE NOTICE 'Room 102: several spaces available (%).', spaces;
    END IF;
END $$;

-- 3. WHILE and numeric FOR
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', i;
        i := i + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', i;
    END LOOP;
END $$;

-- 4. Allocate procedure
CREATE OR REPLACE PROCEDURE allocate_room(
    p_room_id INTEGER,
    p_student_number VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INTEGER;
BEGIN
    IF p_student_number IS NULL OR BTRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid student number: it cannot be blank.';
    END IF;

    SELECT available_bed_spaces INTO v_spaces
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room ID % does not exist.', p_room_id;
    END IF;

    IF v_spaces <= 0 THEN
        RAISE EXCEPTION 'Room % is full.', p_room_id;
    END IF;

    UPDATE hostel_rooms
    SET available_bed_spaces = available_bed_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, allocation_status)
    VALUES (p_student_number, p_room_id, 'ALLOCATED');

    RAISE NOTICE 'Student % allocated to room %.', p_student_number, p_room_id;
END $$;

-- 5. Two valid allocations and one allocation to a full room
CALL allocate_room(1, 'STU001');
CALL allocate_room(2, 'STU002');

-- Make room 2 full, then demonstrate failed allocation.
CALL allocate_room(2, 'STU003');

DO $$
BEGIN
    BEGIN
        CALL allocate_room(2, 'STU004');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Expected failed full-room allocation: %', SQLERRM;
    END;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. Check-out procedure; second call must not free another space
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT room_id, allocation_status
    INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation ID % does not exist.', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETED' THEN
        RAISE NOTICE 'Allocation % is already completed. Bed space will not be released again.',
            p_allocation_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
    SET available_bed_spaces = available_bed_spaces + 1
    WHERE room_id = v_room_id;

    UPDATE allocations
    SET allocation_status = 'COMPLETED'
    WHERE allocation_id = p_allocation_id;

    RAISE NOTICE 'Allocation % checked out successfully.', p_allocation_id;
END $$;

CALL check_out(1);
CALL check_out(1);

-- 7. Explicit cursor for full or nearly full rooms
DO $$
DECLARE
    room_cursor CURSOR FOR
        SELECT room_id, room_name, available_bed_spaces
        FROM hostel_rooms
        WHERE available_bed_spaces <= 1;
    rec RECORD;
BEGIN
    OPEN room_cursor;
    LOOP
        FETCH room_cursor INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full/nearly full room: ID %, %, % spaces left.',
            rec.room_id, rec.room_name, rec.available_bed_spaces;
    END LOOP;
    CLOSE room_cursor;
END $$;

-- 8. Blank student number handled by EXCEPTION
DO $$
BEGIN
    BEGIN
        CALL allocate_room(1, '   ');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Invalid blank student number handled: %', SQLERRM;
    END;
END $$;

-- 9. Final results
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
