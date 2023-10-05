--
-- This script configures the integrated database for the Base62 Key Generator microservice.
-- The microservice's core logic resides within the database functions.
-- The microservice is implemented in PL/PGSQL and employs the CRON Extension for scheduled procedures.
--
-- Author: Luca Corallo
-- Date: 05/10/2023
--

-- DELETION PROCEDURE
-- DDL URL SWIFT
DROP TABLE IF EXISTS base62_key_generator.keys CASCADE;

DROP FUNCTION IF EXISTS base62_key_generator.generate_key;
DROP FUNCTION IF EXISTS base62_key_generator.get_key;
DROP FUNCTION IF EXISTS base62_key_generator.procedure_creation;
DROP FUNCTION IF EXISTS base62_key_generator.procedure_deletion_used_key;

DROP SEQUENCE IF EXISTS sequence_root;
DROP SEQUENCE IF EXISTS sequence_extraction_index;

DROP EXTENSION IF EXISTS pg_cron;

DROP SCHEMA IF EXISTS base62_key_generator;


-- CREATION PROCEDURE
-- DDL BASE62 KEY GENERATOR
CREATE SCHEMA base62_key_generator;

CREATE SEQUENCE sequence_root START 1;
CREATE SEQUENCE sequence_extraction_index START 1;

--
-- This function generates a Base62 key.
--
-- Author: Luca Corallo
-- Date: 05/10/2023
--
CREATE FUNCTION base62_key_generator.generate_key()
RETURNS TEXT
language PLPGSQL
AS $$
  DECLARE
    LOOP_ATTEMPS    INTEGER = 7;  -- The number of LOOP steps. In each step we will take the N bit that will be converted into Base62 character;
    bitsIndex       INTEGER = 0;  -- Index used to track where should be started the substring to extract the character;   
   
    -- We are using 42 Bit because each Base62 character uses 6 bit. Therefore we want save 42/6 = 7 characters;
    binarySequence  TEXT    = ''; -- It is saved as text in order to convert easily in Base62 code;
    b62Character    TEXT    = ''; -- Index used to save temporary the Base62 character saved;
    b62Key          TEXT    = ''; -- Variable used to save the final Base62 key generated;

    -- This is the map which convert the 6 bit in a character;
    CHAR_MAP        JSON    = '{  
      "000000": "0",
      "000001": "1",
      "000010": "2",
      "000011": "3",
      "000100": "4",
      "000101": "5",
      "000110": "6",
      "000111": "7",
      "001000": "8",
      "001001": "9",
      "001010": "A",
      "001011": "B",
      "001100": "C",
      "001101": "D",
      "001110": "E",
      "001111": "F",
      "010000": "G",
      "010001": "H",
      "010010": "I",
      "010011": "J",
      "010100": "K",
      "010101": "L",
      "010110": "M",
      "010111": "N",
      "011000": "O",
      "011001": "P",
      "011010": "Q",
      "011011": "R",
      "011100": "S",
      "011101": "T",
      "011110": "U",
      "011111": "V",
      "100000": "W",
      "100001": "X",
      "100010": "Y",
      "100011": "Z",
      "100100": "a",
      "100101": "b",
      "100110": "c",
      "100111": "d",
      "101000": "e",
      "101001": "f",
      "101010": "g",
      "101011": "h",
      "101100": "i",
      "101101": "j",
      "101110": "k",
      "101111": "l",
      "110000": "m",
      "110001": "n",
      "110010": "o",
      "110011": "p",
      "110100": "q",
      "110101": "r",
      "110110": "s",
      "110111": "t",
      "111000": "u",
      "111001": "v",
      "111010": "w",
      "111011": "x",
      "111100": "y",
      "111101": "z",
      "111110": "+",
      "111111": "-"
    }';
    
  BEGIN
    -- Getting the next value of root sequence. Then convert it into bit and save in binarySequence as text;
    SELECT TEXT(NEXTVAL('sequence_root')::BIT(42)) INTO binarySequence;

    FOR counter in 0..LOOP_ATTEMPS-1 LOOP
      
      -- Get 6 bit proper substring index;
      SELECT LOOP_ATTEMPS*6 - 6*counter into bitsIndex;
      
      -- Get 6 bits proper substring;
      SELECT LEFT(RIGHT(binarySequence, bitsIndex), 6) INTO b62Character;

       -- Concat the mapped Base62 Character into the key variable;
      SELECT CONCAT(b62Key, CHAR_MAP ->> b62Character) INTO b62Key;
    END LOOP;
    RETURN b62Key;
  END;
$$;


CREATE TABLE base62_key_generator.keys (
  key         CHAR(7)                   NOT NULL UNIQUE DEFAULT base62_key_generator.generate_key(),
  created_at  TIMESTAMP WITH TIME ZONE  NOT NULL        DEFAULT now(),
  PRIMARY KEY (key)
);


--
-- This function retrieves a Base62 key from the 'keys' table in the 'base62_key_generator' schema.
-- The function return only one row tracked by index 'sequence_extraction_index'. The index 'sequence_extraction_index' track the next
-- base62key that has never be used as result. This is only the function that should be exposed;
--
-- Author: Luca Corallo
-- Date: 05/10/2023
--
CREATE OR REPLACE FUNCTION base62_key_generator.get_key()
RETURNS base62_key_generator.keys
LANGUAGE PLPGSQL
AS $$
  DECLARE
    result base62_key_generator.keys;
  BEGIN
    SELECT * INTO result 
    FROM base62_key_generator.keys 
    ORDER BY created_at, key ASC 
    LIMIT 1 OFFSET (NEXTVAL('sequence_extraction_index') - 2);

    RETURN result; 
  END;
$$;


--
-- This function creates Base62 keys in the 'base62_key_generator.keys' table to reach a target number of keys.
-- This function should be called by a scheduler.
--
-- Author: Luca Corallo
-- Date: 05/10/2023
--
CREATE FUNCTION base62_key_generator.procedure_creation()
RETURNS VOID
LANGUAGE PLPGSQL
AS $$
  DECLARE
    ACTUAL_KEYS   INTEGER = 0;    -- The actual number of keys in the database;
    N_TARGET_KEYS INTEGER = 1000; -- The number of keys we ever want to have available;
    DIFF          INTEGER = 0;    -- The difference between N_TARGET_KEYS and ACTUAL_KEYS;
  BEGIN
      SELECT COUNT(k.key) FROM base62_key_generator.keys AS k INTO ACTUAL_KEYS;
      SELECT N_TARGET_KEYS - ACTUAL_KEYS INTO DIFF;

      IF DIFF > 0 THEN
        FOR counter in 0..DIFF LOOP
          INSERT INTO base62_key_generator.keys (key, created_at) VALUES (base62_key_generator.generate_key(), now());
        END LOOP;
        
      END IF;
  END;
$$;

--
-- This function deletes used Base62 keys from the 'base62_key_generator.keys' table.
-- The key used are tracked by sequence_extraction_index SEQUENCE
-- This function should be called by a scheduler.
--
-- Author: Luca Corallo
-- Date: 05/10/2023
--
CREATE FUNCTION base62_key_generator.procedure_deletion_used_key()
RETURNS VOID
LANGUAGE PLPGSQL
AS $$
  DECLARE
    extractionIndx BIGINT = 0; -- Index counter which refer to number of keys that has been used;

  BEGIN
      SELECT NEXTVAL('sequence_extraction_index') - 1 INTO extractionIndx;

      IF extractionIndx > 1 THEN

        DELETE FROM base62_key_generator.keys WHERE key IN (
          SELECT key FROM base62_key_generator.keys ORDER BY created_at, key ASC LIMIT (extractionIndx - 1)
        );

        SELECT SETVAL('sequence_extraction_index', 1) INTO extractionIndx;
      END IF;
  END;
$$;

-- Scheduler procedures creation
CREATE EXTENSION pg_cron;

SELECT cron.schedule('scheduler_create_new_keys', '* * * * * *', $$ SELECT base62_key_generator.procedure_creation() $$);
SELECT cron.schedule('scheduler_cleanup_used_keys', '* * * * * *', $$ SELECT base62_key_generator.procedure_deletion_used_key() $$);

-- RLS Policies
GRANT USAGE ON SCHEMA base62_key_generator TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA base62_key_generator TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA base62_key_generator TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA base62_key_generator TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA base62_key_generator GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA base62_key_generator GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA base62_key_generator GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

ALTER TABLE base62_key_generator.keys enable row level security;

CREATE POLICY "Only authorized user can generate a key" ON base62_key_generator.keys FOR SELECT TO authenticated
USING ( (auth.jwt() ->> 'email'::text) = 'admin@event.io'::text );
