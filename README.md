# Base62 Key Generator Microservice
🔐 The Base62Key Generator Microservice creates unique, secure, human-readable keys using Base62 encoding. Ideal for applications requiring compact, easy-to-share keys.
These keys are used to uniquely identify objects or resources within a system.

## Use Case

The Base62 Key Generator microservice serves the purpose of creating unique, random, and secure keys for resources in a system. It is particularly useful in scenarios where you want to provide short, user-friendly, and easily shareable access tokens for various operations.

## Functions

### `base62_key_generator.generate_key()`

This function generates a Base62 key. It operates as follows:

1. Generates a 42-bit binary sequence.
2. Converts the binary sequence into a Base62 key.
3. Returns the generated Base62 key.

### `base62_key_generator.get_key()`

This function retrieves an unused Base62 key from the database. It works as follows:

1. Selects the earliest created, unused key from the `keys` table.
2. Marks the selected key as used to avoid duplication.
3. Returns the selected Base62 key.

### `base62_key_generator.procedure_creation()`

This function creates new Base62 keys in the `keys` table to maintain a specific target number of available keys. It is intended to be called by a scheduler.

### `base62_key_generator.procedure_deletion_used_key()`

This function deletes used Base62 keys from the `keys` table. It is meant to be called by a scheduler. The keys to be deleted are tracked by the `sequence_extraction_index` sequence.

## How It Works

1. **Key Generation**: When `base62_key_generator.generate_key()` is called, it starts by creating a 42-bit binary sequence. This sequence is then converted into a Base62 key by mapping each 6 bits to a Base62 character.

2. **Key Retrieval**: When `base62_key_generator.get_key()` is called, it retrieves the earliest created, unused key from the `keys` table. It ensures that each key is used only once.

3. **Scheduled Procedures**: The microservice has two scheduled procedures:
   - `scheduler_create_new_keys`: Calls `base62_key_generator.procedure_creation()` to create new keys if the number of available keys falls below a certain threshold.
   - `scheduler_cleanup_used_keys`: Calls `base62_key_generator.procedure_deletion_used_key()` to delete used keys, keeping the database tidy.

4. **Security Policies**: Only authenticated users with the email address 'admin@event.io' can generate keys, as defined by the RLS policy.

5. **Row Level Security**: RLS is enforced to restrict access based on user roles, ensuring that users can only access the keys they are allowed to.

6. **Schema and Extension**: The microservice utilizes the `base62_key_generator` schema for organization and the `pg_cron` extension for scheduling procedures.

7. **Character Map**: A JSON `CHAR_MAP` is used to map 6 bits to their respective Base62 characters during key generation.

The Base62 Key Generator microservice provides a robust and secure mechanism for generating and managing access keys in a system, ensuring smooth operations and controlled access to resources.
