-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Replace STUDENT_NUMBER in the filename with your student number before submission.

DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP PROCEDURE IF EXISTS dispense_medicine(INTEGER, VARCHAR, INTEGER);
DROP PROCEDURE IF EXISTS reverse_dispensing(INTEGER);

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INTEGER NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    dispensing_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(30) NOT NULL,
    quantity INTEGER NOT NULL,
    dispensing_status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
        CHECK (dispensing_status IN ('DISPENSED', 'REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
('Paracetamol', 20),
('Amoxicillin', 5),
('Oral Rehydration Salts', 12);

-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    stock INTEGER;
BEGIN
    SELECT stock_quantity INTO stock
    FROM medicines WHERE medicine_id = 2;

    IF stock = 0 THEN
        RAISE NOTICE 'Amoxicillin: out of stock.';
    ELSIF stock <= 5 THEN
        RAISE NOTICE 'Amoxicillin: low on stock (% remaining).', stock;
    ELSE
        RAISE NOTICE 'Amoxicillin: sufficiently stocked (% remaining).', stock;
    END IF;
END $$;

-- 3. WHILE and numeric FOR
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Stock review day %', i;
        i := i + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- 4. Dispense procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id INTEGER,
    p_student_number VARCHAR,
    p_quantity INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: must be greater than zero.';
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine ID % does not exist.', p_medicine_id;
    END IF;

    IF p_quantity > v_stock THEN
        RAISE EXCEPTION 'Insufficient stock. Requested %, available %.',
            p_quantity, v_stock;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records
        (medicine_id, student_number, quantity, dispensing_status)
    VALUES
        (p_medicine_id, p_student_number, p_quantity, 'DISPENSED');

    RAISE NOTICE 'Medicine dispensed successfully.';
END $$;

-- 5. Two valid quantities and one quantity exceeding stock
CALL dispense_medicine(1, 'STU001', 4);
CALL dispense_medicine(2, 'STU002', 2);

DO $$
BEGIN
    BEGIN
        CALL dispense_medicine(2, 'STU003', 10);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Expected failed dispensing: %', SQLERRM;
    END;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY dispensing_id;

-- 6. Reverse procedure; second call must not restore stock again
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_dispensing_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INTEGER;
    v_quantity INTEGER;
    v_status VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, dispensing_status
    INTO v_medicine_id, v_quantity, v_status
    FROM dispensing_records
    WHERE dispensing_id = p_dispensing_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record ID % does not exist.', p_dispensing_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % is already reversed. Stock will not be restored again.',
            p_dispensing_id;
        RETURN;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity + v_quantity
    WHERE medicine_id = v_medicine_id;

    UPDATE dispensing_records
    SET dispensing_status = 'REVERSED'
    WHERE dispensing_id = p_dispensing_id;

    RAISE NOTICE 'Dispensing record % reversed successfully.', p_dispensing_id;
END $$;

CALL reverse_dispensing(1);
CALL reverse_dispensing(1);

-- 7. Explicit cursor for medicines below low-stock threshold
DO $$
DECLARE
    medicine_cursor CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity < 5;
    rec RECORD;
BEGIN
    OPEN medicine_cursor;
    LOOP
        FETCH medicine_cursor INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock: ID %, %, % remaining.',
            rec.medicine_id, rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE medicine_cursor;
END $$;

-- 8. Negative dispensing quantity handled by EXCEPTION
DO $$
BEGIN
    BEGIN
        CALL dispense_medicine(1, 'STU004', -2);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Invalid negative quantity handled: %', SQLERRM;
    END;
END $$;

-- 9. Final results
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY dispensing_id;
