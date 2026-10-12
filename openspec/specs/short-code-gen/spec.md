# short-code-gen Specification

## Purpose

Generate exact, non-sequential Base62 identifiers within the user-approved 32-bit ID capacity.

## Requirements

### Requirement: Short code generation

The system SHALL generate short codes using a two-phase algorithm: golden ratio obfuscation followed by Base62 encoding.

#### Scenario: Generate code from sequential ID

- **GIVEN** a sequential positive integer ID (e.g., 1)
- **WHEN** the system generates a short code
- **THEN** the resulting code SHALL be a Base62 string of at least 6 characters
- **AND** the code SHALL be non-sequential; the reversible permutation SHALL NOT be treated as an authorization token

#### Scenario: Different IDs produce different codes

- **GIVEN** two different sequential IDs (e.g., 1 and 2)
- **WHEN** the system generates short codes for both
- **THEN** the two codes SHALL be different

#### Scenario: Minimum code length guarantee

- **GIVEN** any valid positive integer ID
- **WHEN** the system generates a short code
- **THEN** the Base62-encoded code SHALL have at least 6 characters
- **BECAUSE** the base offset ensures obfuscated value >= 62^5

### Requirement: Base62 encoding

The system SHALL encode integers using Base62 with character set `0-9a-zA-Z`.

#### Scenario: Encode zero

- **GIVEN** the integer 0
- **WHEN** the system encodes it to Base62
- **THEN** the result SHALL be "0"

#### Scenario: Encode maximum value

- **GIVEN** the maximum mapped 32-bit value plus the Base62 length offset
- **WHEN** the system encodes it to Base62
- **THEN** the result SHALL be a valid Base62 string
- **AND** decoding it back SHALL produce the original integer

### Requirement: Golden ratio obfuscation

The system SHALL obfuscate sequential IDs using golden ratio multiplication to produce non-sequential output values.

#### Scenario: Obfuscation produces non-sequential output

- **GIVEN** sequential IDs 1, 2, 3
- **WHEN** the system applies golden ratio obfuscation
- **THEN** the output values SHALL NOT be sequential
- **AND** the outputs SHALL appear randomly distributed

#### Scenario: Collision detection

- **GIVEN** a range of sequential IDs from 1 to 100000
- **WHEN** the system applies golden ratio obfuscation to all IDs
- **THEN** no two different IDs SHALL produce the same obfuscated value

### Requirement: Exact bounded ID space

The system SHALL generate codes using exact 32-bit modular arithmetic on LuaJIT and SHALL reject IDs outside 0..4294967295.

#### Scenario: Boundary values remain distinct

- **GIVEN** IDs near 2^22, 2^31 and 2^32-1
- **WHEN** codes are generated and reversed
- **THEN** the exact input IDs SHALL be recovered without floating point loss

#### Scenario: Overflow does not wrap

- **GIVEN** an ID of 4294967296 or a fractional ID
- **WHEN** code generation is attempted
- **THEN** the input SHALL be rejected rather than generating a previously used code
