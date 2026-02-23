# Spreadsheet Sanity Checker

A small Rails application for uploading and validating spreadsheets (CSV / Excel) and importing property & unit data.

---

## Quick links
- Routes: [`config/routes.rb`](config/routes.rb)
- Database config: [`config/database.yml`](config/database.yml)
- Example .env file: [`.env.example`](.env.example)
- Ruby version: [`.ruby-version`](.ruby-version)
- Gemfile: [`Gemfile`](Gemfile)
- Local setup helper: [`bin/setup`](bin/setup)

---

## Requirements

- Ruby: see [`.ruby-version`](.ruby-version) (this repo uses Ruby 3.4.8)
- PostgreSQL (development/test use PostgreSQL per [config/database.yml](config/database.yml))

---

## Environment

This application uses environment variables for configuration. A template file is provided:

### 1. Copy the example environment file
```bash
cp .env.example .env
```

### 2. Configure your credentials
Edit the `.env` file and update the database credentials for your local PostgreSQL installation:
```
DB_USERNAME=your_postgres_username    # Often 'postgres' or your system username
DB_PASSWORD=your_postgres_password    # Your PostgreSQL password (if any)
```
Optionally, you can also configure the `PORT` the application should run on (default is 4000).

### 3. Run setup
Run the setup script to install dependencies and create the database:
```
bin/setup
```

This command will:

- Install required Ruby gems

- Create and configure the PostgreSQL databases for development and test

- Load the database schema

### 4. Start the application
```
bin/rails server
```

Open http://localhost:4000 (or your custom port) and the app root (property_imports#new) will be available (see [`config/routes.rb`](config/routes.rb)).

---

## CSV / Excel Import Behavior

- Expected headers are defined in the code ([`ImportConfig`](app/services/import_config.rb)) and validated during processing.
- After previewing an import, the user can "execute" the import which uses an import transaction flow handled via [`PropertyImportsController`](app/controllers/property_imports_controller.rb). The controller utilizes the following services:
- File parsing and cleaning: [`CsvProcessingService`](app/services/csv_processing_service.rb)
- Adding new property / unit records to database: [`ImportTransactionService`](app/services/import_transaction_service.rb)

## Duplicate Properties

- Each [`Property`](app/models/property.rb) is identified by its unique `building_name` -- no two properties can share the same name, even at different addresses.
- Each [`Unit`](app/models/unit.rb) is associated with one `Property`.
- A `Property` cannot contain multiple instances of the same `Unit`.
- Any `Property` that appears only once in an import with NO `Unit` listed is assumed to be "single-family". Conversely, any `Property` with at least one associated `Unit` is treated as "multi-family".
- Each physical address (`street_address, city, state, zip_code` combination) can only belong to one property -- this is based on the assumption that no two different properties are allowed to claim the exact same location.

- During import validation, the system checks for duplicates in two places:

    - Database: Compares against existing property records

    - Import file: Compares against other rows in the same upload

### Validation Rules
| Scenario | Result  | Example |
| -------- | -------- | -------- |
| Same building name + same address | Valid - Property already exists (marked as "Already in database", no action taken) | DB: "Ave Apts" at 123 Main St, Import: "Ave Apts" at 123 Main St
| Same building name + same address + new unit | Valid - Will create new unit | DB: "Ave Apts" at 123 Main St (associated with 2 Unit records: 101 and 102), Import: "Ave Apts" at 123 Main St, Unit 103
| Same building name + different address | Error - Building name already in use elsewhere | DB: "Ave Apts" at 123 Main St, Import: "Ave Apts" at 456 Oak Ave
| Different building name + same address | Error - Address already belongs to another property | DB: "Ave Apts" at 123 Main St, Import: "Oak Heights" at 123 Main St
| Completely new building + new address | Valid - Will create new property | No matching name or address in system
| Missing one or more of: Building Name, Street Address, City, State, ZIP Code | Error - Missing required field(s) | "Ave Apts" at [blank address]

## Additional Assumptions
- All `Properties` will be located in the US.
- Uploaded spreadsheets will always be in the same format (although minimal handling for the alternative scenario does exist in [`CsvProcessingService`](app/services/csv_processing_service.rb)'s `validate_headers()`).
- Users of this software should not have the direct ability to edit or delete:
    1. Records of imports, or
    2. Actual imports

    from the database. However, the ability to view records of past imports is OK.

## Tradeoffs
### Strict Validation vs Ease of Use
- Ideally, the user should not have to care about inconsequential, easily-corrected errors such as extra whitespace, accidental punctuation, or differences in capitalization. Thus, issues like these are normalized/cleaned under the hood with no need for manual intervention (see [`Property`](app/models/property.rb) and [`CsvProcessingService`](app/services/csv_processing_service.rb)).
Unfortunately, more involved errors (e.g. a typo in a state name) are not auto-corrected as handling these would require a disproportionate increase in the complexity of validation/cleaning (for example, adding fuzzy matching).

- On a similar note, it would be convenient for a user to have the ability to correct minor errors within the app's UI. However:
    - Without making the app reactive, feedback on current validation state would have to wait until the next form submission
    - There would be potential for nigh-endless redirect loops in the form of "this needs correcting" --> correct it --> "nope, now it has a new problem / this other thing needs correcting"
    - The above flow would make keeping track of "data versioning" more complex (state of original spreadsheet data vs data on the screen vs data in the database), requiring validation at each step and increasing the potential for errors
    - As the number of spreadsheet rows increases, the convenience of in-app editing decreases. At the point that a file contains, say, 50+ rows, it would likely be easier to open it in Excel (which already includes all necessary editing functionality) and find/replace as needed.

### Robustness vs Simplicity
- This is an internal tool, so authentication was not a concern. However, one requirement was to "catch obvious mistakes BEFORE anything is permanently saved," which presented the decision of how best to store the temporary data.
- Since the import data does not need to 1. be associated with an authenticated user/login or 2. persist for long periods before being added to the database, perhaps the simplest option would be to store the data on the session. But we are dealing with file imports, which session size limits cannot reliably accommodate.
- Alternatively, to emulate aspects of session storage, we could utilize the low-level Rails cache and assign each entry containing import data a key (perhaps using the session ID). But, like session storage, this still requires some level of data transformation just to be able to temporarily store the data prior to processing. For example, what would the nested keys/values of each cache entry look like? Should we transform the data to the form needed by the database prior to adding it to the cache? Prior to displaying it on the page? After? Also, we would have to read data from the cache many times per import, which might introduce latency, and the Rails cache does not support short-lived, automatic expiration, so we would need to remember to perform manual cleanup.
- Neither of the above options have any built-in solution to allow for the creation of records of imports (or import attempts), which could be useful for debugging in the event of an error.
- Considering all this,  we chose to store import data directly in the database using dedicated `PropertyImport` and `PropertyImportRow` models. This approach offers several advantages:

    - No size limitations - Database storage can accommodate files of any reasonable size without the constraints of session or cache storage.
    - Built-in audit trail - Every import attempt creates persistent records with timestamps, status tracking, and detailed error summaries, making debugging and historical analysis straightforward.
    - Transactional integrity - By wrapping the entire import process in a database transaction (see [`CsvProcessingService`](app/services/csv_processing_service.rb)`process()`), we ensure that either all rows are successfully processed or none are. If validation fails, the transaction rolls back, leaving no partial data.
    - Preview without persistence - Imported data is stored in `property_import_rows` with a `pending` status, allowing users to review and validate before finalizing. Only when the user explicitly confirms the import (via [`ImportTransactionService`](app/services/import_transaction_service.rb)) do we:
        - Create actual `Property` and `Unit` records
        - Update import row statuses to `imported`
        - Link created records via `created_property_id` and `existing_property_id`
    - Clean separation of concerns - Raw uploaded data is stored in `original_data` (JSONB), while cleaned/normalized data ready for validation lives in `parsed_data` (JSONB). This preserves the original input for debugging while ensuring consistent validation.
    - File processing with Roo - The [`CsvProcessingService`](app/services/csv_processing_service.rb) uses the Roo gem to parse uploaded spreadsheets. Roo reads directly from the uploaded file's tempfile location (via file.path), avoiding unnecessary file I/O operations. This approach:
        - Uses Rails' built-in file upload handling (no custom tempfile management)
        - Supports CSV, Excel (.xlsx), and OpenOffice (.ods) formats

## Potential Improvements
- For consistency and clarity, properties designated as "single-family" may benefit from the creation of associated `Unit` entries (perhaps with a specific `unit_number` like "SF"). The handling of "single-family" vs "multi-family" could also stand to be more robust in general. For example, right now, if there were:
    - a single row representing a property in a given file,
    - and that row lacked a `unit_number`,
    - and the user did not catch the discrepancy during preview

    ...the property could be imported to the database erroneously as "single-family," requiring manual intervention upon discovery.
- We could consider utilizing an API (for example, Google Maps) for address validation and normalization (think "123 Test St" vs "123 Test Street" -- which at the moment would be considered two distinct street addresses -- or confirming that the ZIP code is correct for a given address...or even autofilling missing data, although this would require careful handling and may not be worth the risk).
- We should add more simple coverage for basic formatting errors, e.g. handling empty row(s) before headers.
- To bridge the gap between ease of use and concerns re: data integrity and complexity, could consider adding functionality to allow the user to re-download their uploaded file with rows containing errors visually highlighted.
- Alternatively, we could allow for very simple changes to be made via the app's UI. For example, right now, a duplicate unit row will block the entire import. This approach ensures safety but is cumbersome. It probably wouldn't be too bad to allow for simple deletion of problematic rows in the `#preview` view.