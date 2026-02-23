class CsvProcessingService
  include DataCleaner
  include ImportConfig

  attr_reader :import, :file, :errors

  REQUIRED_HEADERS = Headers::ALL
  US_STATES = Property::US_STATES

  def initialize(import, file)
    @import = import
    @file = file
    @errors = []
  end

  # ==================================================
  # MAIN PROCESSING FLOW
  # ==================================================

  # Purpose: Handles the entire CSV import process within a database transaction
  # Steps:
  #   1. Parse the uploaded file into row structures
  #   2. Validate that required headers are present
  #   3. Create import rows (properties and units)
  #   4. Validate all created rows
  #   5. Update import status to previewed with summary
  #   6. Handle any errors with rollback
  def process
    ActiveRecord::Base.transaction do
      begin
        rows = parse_file
        validate_headers!(rows.first)
        create_import_rows(rows)
        validate_rows
        import.update!(
          status: :previewed,
          summary: build_summary
        )
        true
      rescue => e
        @errors << e.message
        import.update!(status: :failed, error_summary: { errors: @errors })
        raise ActiveRecord::Rollback
      end
    end
  end

  private

    # ==================================================
    # FILE PARSING
    # ==================================================

    # Purpose: Reads and parses the uploaded CSV/Excel file
    # Steps:
    #   1. Create temp file from upload
    #   2. Open spreadsheet with Roo
    #   3. Extract headers from first row
    #   4. Iterate through remaining rows, building data hashes
    #   5. Filter out empty rows
    #   6. Clean up temp file
    # Returns: Array of row hashes with :data and :row_number
    def parse_file
      spreadsheet = Roo::Spreadsheet.open(file.path)

      headers = spreadsheet.row(1).map(&:to_s).map(&:strip)
      rows = []

      (2..spreadsheet.last_row).each do |i|
        row_data = {}
        row = spreadsheet.row(i)

        headers.each_with_index do |header, index|
          value = row[index]
          row_data[header] = value.to_s.strip if header.present?
        end

        if row_data.values.any?(&:present?)
          rows << {
            data: row_data,
            row_number: i
          }
        end
      end

      rows
    end

    # Purpose: Ensures all required headers are present in the import file
    # Steps:
    #   1. Extract headers from first row data
    #   2. Compare with REQUIRED_HEADERS constant
    #   3. Raise error if any headers are missing
    def validate_headers!(first_row)
      return unless first_row

      row_data = first_row.is_a?(Hash) && first_row.key?(:data) ? first_row[:data] : first_row

      headers = row_data.keys.compact.map(&:to_s).map(&:strip)
      missing_headers = REQUIRED_HEADERS - headers

      if missing_headers.any?
        raise "Missing required columns: #{missing_headers.join(', ')}"
      end
    end

    # ==================================================
    # IMPORT ROW CREATION
    # ==================================================

    # Purpose: Creates property and unit import records from parsed data
    # Steps:
    #   1. Group data rows by building composite key (deduplicate buildings)
    #   2. Create property rows from deduplicated building data
    #   3. Create unit rows from original data (preserving all units)
    def create_import_rows(data_rows)
      building_data = data_rows
        .group_by { |item|
          [
            clean_building_name(item[:data][Headers::BUILDING_NAME]),
            clean_street_address(item[:data][Headers::STREET_ADDRESS]),
            clean_city(item[:data][Headers::CITY]),
            clean_state(item[:data][Headers::STATE]),
            clean_zip_code(item[:data][Headers::ZIP_CODE])
          ].compact.join("|")
        }
        .transform_values(&:first)

      create_property_rows(building_data)
      create_unit_rows(data_rows)
    end

    # Purpose: Creates property-type import rows for each unique building
    # Steps:
    #   1. Iterate through deduplicated building data
    #   2. Create import row with record_type = :property
    def create_property_rows(building_data)
      building_data.each do |_key, item|
        create_import_row(:property, item)
      end
    end

    # Purpose: Creates unit-type import rows for rows containing unit numbers
    # Steps:
    #   1. Filter data rows to only those with unit numbers
    #   2. Create import row for each with record_type = :unit
    def create_unit_rows(data_rows)
      data_rows
        .select { |item| item[:data][Headers::UNIT].present? }
        .each do |item|
          create_import_row(:unit, item)
        end
    end

    # Purpose: Creates a single import row record in the database
    # Steps:
    #   1. Build parsed data based on record type
    #   2. Create PropertyImportRow with original data, parsed data, and pending status
    def create_import_row(record_type, item)
      row_data = item[:data]
      original_row_number = item[:row_number]

      import.property_import_rows.create!(
        record_type: record_type,
        original_data: row_data.merge("_original_row" => original_row_number),
        parsed_data: build_parsed_data(record_type, row_data),
        status: :pending
      )
    end

    # Purpose: Transforms raw row data into standardized parsed format
    # Steps:
    #   1. Apply cleaning methods to each field
    #   2. Include unit number only for unit records
    def build_parsed_data(record_type, row_data)
      parsed = {
        ParsedKeys::BUILDING_NAME => clean_building_name(row_data[Headers::BUILDING_NAME]),
        ParsedKeys::STREET_ADDRESS => clean_street_address(row_data[Headers::STREET_ADDRESS]),
        ParsedKeys::CITY => clean_city(row_data[Headers::CITY]),
        ParsedKeys::STATE => clean_state(row_data[Headers::STATE]),
        ParsedKeys::ZIP_CODE => clean_zip_code(row_data[Headers::ZIP_CODE])
      }
        # If unit record, include unit number
        parsed[ParsedKeys::UNIT_NUMBER] = clean_unit_number(row_data[Headers::UNIT]) if record_type == :unit

      parsed
    end

    # ==================================================
    # ROW VALIDATION
    # ==================================================

    # Purpose: Handles validation for all property and unit rows
    # Steps:
    #   1. Validate all property rows
    #   2. Validate all unit rows
    def validate_rows
      import.property_import_rows.properties.find_each { |row| validate_property_row(row) }
      import.property_import_rows.units.find_each { |row| validate_unit_row(row) }
    end

    # Purpose: Performs comprehensive validation for a property row
    # Steps:
    #   1. Check for required fields
    #   2. Validate state format
    #   3. Check for exact database match
    #   4. Check for building name conflicts (database and import)
    #   5. Check for address conflicts (if no building name conflict)
    #   6. Update row with errors
    #
    def validate_property_row(row)
      errors = []
      data = row.parsed_data

      add_required_field_errors(errors, data)
      add_state_validation_error(errors, data)

      # Check for exact database match first
      if data[ParsedKeys::BUILDING_NAME].present?
        # Check for exact database match first
        exact_match_found = check_exact_database_match(row, data, errors)

        # Only check conflicts if no exact match was found
        unless exact_match_found
          check_database_building_name_conflict(row, data, errors)
          check_import_building_name_conflict(row, data, errors)
        end
      end
      # Only check address conflicts if no building name conflict was found
      if errors.none? { |e| e.include?("'#{data[ParsedKeys::BUILDING_NAME]}'") }
        check_database_address_conflict(row, data, errors)
        check_import_address_conflict(row, data, errors)
      end

      row.update_status_and_errors(errors)
    end

    # Purpose: Performs validation for a unit row
    # Steps:
    #   1. Check for required fields
    #   2. Validate parent property exists
    #   3. Check for duplicate units
    #   4. Update row with errors
    def validate_unit_row(row)
      errors = []
      data = row.parsed_data

      add_required_field_errors(errors, data)

      if data[ParsedKeys::BUILDING_NAME].present?
        check_parent_property(row, data, errors)
        check_unit_duplicates(row, data, errors)
      end

      row.update_status_and_errors(errors)
    end

    # ==================================================
    # VALIDATION HELPERS - FIELD CHECKS
    # ==================================================

    # Purpose: Validates presence of all required fields
    # Steps:
    #   1. Check each required field for presence
    #   2. Add specific error messages for missing fields
    #   3. For units, also validate unit number presence
    def add_required_field_errors(errors, data)
      errors << "Building name is required" if data[ParsedKeys::BUILDING_NAME].blank?
      errors << "Street address is required" if data[ParsedKeys::STREET_ADDRESS].blank?
      errors << "City is required" if data[ParsedKeys::CITY].blank?
      errors << "State is required" if data[ParsedKeys::STATE].blank?
      errors << "ZIP code is required" if data[ParsedKeys::ZIP_CODE].blank?

      if data[:record_type] == "unit"
        errors << "Unit number is required" if data[ParsedKeys::UNIT_NUMBER].blank?
      end
    end

    # Purpose: Validates that state is a valid US state
    # Steps:
    #   1. Check if state exists in US_STATES constant
    #   2. Add error if invalid
    def add_state_validation_error(errors, data)
      state = data[ParsedKeys::STATE]
      if state.present? && !US_STATES.include?(state)
        errors << "'#{state}' is not a valid US state"
      end
    end

    # ==================================================
    # VALIDATION HELPERS - EXACT DATABASE MATCH
    # ==================================================

    # Purpose: Checks if a property with exact matching data already exists in database
    # Steps:
    #   1. Look for property with same building name AND all address fields
    #   2. If found, mark the row as existing_property (no errors, this is valid)
    #   3. Returns true if match found, false otherwise
    def check_exact_database_match(row, data, errors)
      existing = Property.find_by(
        building_name: data[ParsedKeys::BUILDING_NAME],
        street_address: data[ParsedKeys::STREET_ADDRESS],
        city: data[ParsedKeys::CITY],
        state: data[ParsedKeys::STATE],
        zip_code: data[ParsedKeys::ZIP_CODE]
      )

      if existing
        row.update(existing_property: existing)
        # No errors -- this is a valid case
        return true
      end

      false
    end

    # ==================================================
    # VALIDATION HELPERS - BUILDING NAME CONFLICTS
    # ==================================================

    # Purpose: Checks for building name conflicts with existing database records
    # Steps:
    #   1. Find property with same building name in database
    #   2. If found and addresses differ, add conflict error
    def check_database_building_name_conflict(row, data, errors)
      existing = Property.find_by(building_name: data[ParsedKeys::BUILDING_NAME])
      return unless existing

      row.update(existing_property: existing)

      if addresses_differ?(existing, data)
        existing_address = "#{existing.street_address}, #{existing.city}, #{existing.state} #{existing.zip_code}"
        errors << building_name_conflict_message(data, existing_address)
      end
    end

    # Purpose: Checks for building name conflicts within the import file
    # Steps:
    #   1. Find verified property with same building name but different address
    #   2. Add conflict error if found
    def check_import_building_name_conflict(row, data, errors)
      duplicate = find_duplicate_building_name_in_import(row, data)
      return unless duplicate

      errors << building_name_import_conflict_message(data, duplicate)
    end

    # Purpose: Compares address fields between property and data
    # Returns: Boolean indicating if any address field differs
    def addresses_differ?(property, data)
      property.street_address != data[ParsedKeys::STREET_ADDRESS] ||
      property.city != data[ParsedKeys::CITY] ||
      property.state != data[ParsedKeys::STATE] ||
      property.zip_code != data[ParsedKeys::ZIP_CODE]
    end

    # Purpose: Finds duplicate building name with different address in import
    # Steps:
    #   1. Query verified property rows with same building name
    #   2. Exclude current row
    #   3. Exclude rows with matching address (these are not conflicts)
    # Returns: First matching duplicate row or nil
    def find_duplicate_building_name_in_import(row, data)
      import.property_import_rows
        .properties
        .verified
        .where("parsed_data->>'building_name' = ?", data[ParsedKeys::BUILDING_NAME])
        .where.not(id: row.id)
        .where.not(
          "parsed_data->>'street_address' = ? AND parsed_data->>'city' = ? AND parsed_data->>'state' = ? AND parsed_data->>'zip_code' = ?",
          data[ParsedKeys::STREET_ADDRESS],
          data[ParsedKeys::CITY],
          data[ParsedKeys::STATE],
          data[ParsedKeys::ZIP_CODE]
        )
        .first
    end

    # ==================================================
    # VALIDATION HELPERS - ADDRESS CONFLICTS
    # ==================================================

    # Purpose: Checks if address already exists in database with different building name
    # Steps:
    #   1. Find property with exact address match
    #   2. If found and building names differ, add conflict error
    def check_database_address_conflict(row, data, errors)
      # Skip if this row already has an exact match (handled earlier)
      return if row.existing_property.present?

      existing = Property.find_by(
        street_address: data[ParsedKeys::STREET_ADDRESS],
        city: data[ParsedKeys::CITY],
        state: data[ParsedKeys::STATE],
        zip_code: data[ParsedKeys::ZIP_CODE]
      )

      if existing && existing.building_name != data[ParsedKeys::BUILDING_NAME]
        errors << address_conflict_message(data, existing)
      end
    end

    # Purpose: Checks for duplicate addresses within import file
    # Steps:
    #   1. Find verified property row with matching address
    #   2. Add conflict error if found
    def check_import_address_conflict(row, data, errors)
      duplicate = find_duplicate_address_in_import(row, data)
      return unless duplicate

      errors << duplicate_address_message(duplicate)
    end

    # Purpose: Finds duplicate address in import file
    # Steps:
    #   1. Query verified property rows with matching address fields
    #   2. Exclude current row
    # Returns: First matching duplicate row or nil
    def find_duplicate_address_in_import(row, data)
      import.property_import_rows
        .properties
        .verified
        .where.not(id: row.id)
        .where("parsed_data->>'street_address' = ?", data[ParsedKeys::STREET_ADDRESS])
        .where("parsed_data->>'city' = ?", data[ParsedKeys::CITY])
        .where("parsed_data->>'state' = ?", data[ParsedKeys::STATE])
        .where("parsed_data->>'zip_code' = ?", data[ParsedKeys::ZIP_CODE])
        .first
    end

    # ==================================================
    # VALIDATION HELPERS - UNIT CHECKS
    # ==================================================

    # Purpose: Validates parent property exists for unit
    # Steps:
    #   1. Check for property in import with same building name
    #   2. Check for property in database with same building name
    #   3. Add error if neither exists
    #   4. If exists, validate address match
    def check_parent_property(row, data, errors)
      property_in_import = find_property_in_import(data[ParsedKeys::BUILDING_NAME])
      property_in_db = Property.find_by(building_name: data[ParsedKeys::BUILDING_NAME])

      if property_in_db.nil? && property_in_import.nil?
        errors << parent_property_missing_message(data)
      elsif property_in_import&.rejected?
        errors << parent_property_invalid_message(data)
      else
        property = property_in_db || property_in_import&.existing_property
        validate_property_address_match(property, data, errors) if property
      end
    end

    # Purpose: Finds property in import by building name
    def find_property_in_import(building_name)
      import.property_import_rows
        .properties
        .where("parsed_data->>'building_name' = ?", building_name)
        .first
    end

    # Purpose: Validates that unit's address matches parent property
    # Steps:
    #   1. Compare each address field with property's address
    #   2. Add error for each mismatched field
    def validate_property_address_match(property, data, errors)
      if property.street_address != data[ParsedKeys::STREET_ADDRESS]
        errors << address_field_mismatch_message(
          "Street address",
          data[ParsedKeys::BUILDING_NAME],
          property.street_address,
          data[ParsedKeys::STREET_ADDRESS]
        )
      end
      if property.city != data[ParsedKeys::CITY]
        errors << address_field_mismatch_message(
          "City",
          data[ParsedKeys::BUILDING_NAME],
          property.city,
          data[ParsedKeys::CITY]
        )
      end
      if property.state != data[ParsedKeys::STATE]
        errors << state_mismatch_message(data, property.state)
      end
      if property.zip_code != data[ParsedKeys::ZIP_CODE]
        errors << address_field_mismatch_message(
          "ZIP code",
          data[ParsedKeys::BUILDING_NAME],
          property.zip_code,
          data[ParsedKeys::ZIP_CODE]
        )
      end
    end

    # Purpose: Handles duplicate unit checks
    # Steps:
    #   1. Check for duplicate in import
    #   2. Check for duplicate in database
    def check_unit_duplicates(row, data, errors)
      return unless data[ParsedKeys::BUILDING_NAME].present? && data[ParsedKeys::UNIT_NUMBER].present?

      check_import_unit_duplicate(row, data, errors)
      check_database_unit_duplicate(data, errors)
    end

    # Purpose: Checks for duplicate unit within import file
    def check_import_unit_duplicate(row, data, errors)
      if find_unit_duplicate_in_import(row, data)
        errors << duplicate_unit_message(data)
      end
    end

    # Purpose: Finds duplicate unit in import
    # Steps:
    #   1. Query verified unit rows with same building name and unit number
    #   2. Exclude current row
    def find_unit_duplicate_in_import(row, data)
      import.property_import_rows
        .units
        .verified
        .where(
          "parsed_data->>'building_name' = ? AND parsed_data->>'unit_number' = ?",
          data[ParsedKeys::BUILDING_NAME], data[ParsedKeys::UNIT_NUMBER]
        )
        .where.not(id: row.id)
        .exists?
    end

    # Purpose: Checks for duplicate unit in database
    def check_database_unit_duplicate(data, errors)
      property = Property.find_by(building_name: data[ParsedKeys::BUILDING_NAME])
      if property && property.units.exists?(unit_number: data[ParsedKeys::UNIT_NUMBER])
        errors << existing_unit_message(data)
      end
    end

    # ==================================================
    # SUMMARY BUILDING
    # ==================================================

    # Purpose: Builds comprehensive summary hash of import results
    # Steps:
    #   1. Count total rows by status and type
    #   2. Count properties vs units
    #   3. Count verified vs rejected
    #   4. Count new vs existing properties
    #   5. Build detailed property breakdown
    def build_summary
      property_rows = import.property_import_rows.properties
      unit_rows = import.property_import_rows.units
      verified_rows = import.property_import_rows.verified
      rejected_rows = import.property_import_rows.rejected

      {
        total_rows: import.property_import_rows.count,
        by_status: import.property_import_rows.group(:status).count,
        by_record_type: import.property_import_rows.group(:record_type).count,
        properties: property_rows.count,
        units: unit_rows.count,
        verified_rows: verified_rows.count,
        rejected_rows: rejected_rows.count,
        new_properties: property_rows.verified.where(existing_property_id: nil).count,
        existing_properties: property_rows.verified.where.not(existing_property_id: nil).count,
        property_breakdown: build_property_breakdown
      }
    end

    # Purpose: Builds detailed breakdown by property
    # Steps:
    #   1. Iterate through verified property rows
    #   2. Count units under each property
    #   3. Build hash with address info and unit count
    def build_property_breakdown
      breakdown = {}

      import.property_import_rows.properties.verified.find_each do |property_row|
        building_name = property_row.parsed_data[ParsedKeys::BUILDING_NAME]
        units = import.property_import_rows
          .units
          .verified
          .where("parsed_data->>'building_name' = ?", building_name)
          .count

        breakdown[building_name] = {
          address: property_row.parsed_data[ParsedKeys::STREET_ADDRESS],
          city: property_row.parsed_data[ParsedKeys::CITY],
          state: property_row.parsed_data[ParsedKeys::STATE],
          zip: property_row.parsed_data[ParsedKeys::ZIP_CODE],
          unit_count: units,
          is_new: property_row.existing_property_id.nil?
        }
      end

      breakdown
    end

    # ==================================================
    # ERROR MESSAGES
    # ==================================================

    def parent_property_missing_message(data)
      "Building '#{data[ParsedKeys::BUILDING_NAME]}' not found in database or import file"
    end

    def parent_property_invalid_message(data)
      "Cannot add unit - building '#{data[ParsedKeys::BUILDING_NAME]}' has validation errors"
    end

    def address_field_mismatch_message(field_name, building_name, expected_value, actual_value)
      "#{field_name} should be '#{expected_value}' for building '#{building_name}' (found '#{actual_value}')"
    end

    def state_mismatch_message(data, expected_state)
      "State should be '#{expected_state}' for building '#{data[ParsedKeys::BUILDING_NAME]}' (found '#{data[ParsedKeys::STATE]}')"
    end

    def duplicate_unit_message(data)
      "Unit #{data[ParsedKeys::UNIT_NUMBER]} for building '#{data[ParsedKeys::BUILDING_NAME]}' appears multiple times in import file"
    end

    def existing_unit_message(data)
      "Unit #{data[ParsedKeys::UNIT_NUMBER]} already exists for building '#{data[ParsedKeys::BUILDING_NAME]}' in database"
    end

    def building_name_conflict_message(data, existing_address)
      "Building name '#{data[ParsedKeys::BUILDING_NAME]}' already exists in database with different address: #{existing_address}"
    end

    def building_name_import_conflict_message(data, duplicate)
      "Building name '#{data[ParsedKeys::BUILDING_NAME]}' appears at row #{duplicate.original_data['_original_row']} with address: #{duplicate.parsed_data[ParsedKeys::STREET_ADDRESS]}, #{duplicate.parsed_data[ParsedKeys::CITY]}, #{duplicate.parsed_data[ParsedKeys::STATE]} #{duplicate.parsed_data[ParsedKeys::ZIP_CODE]}"
    end

    def address_conflict_message(data, existing_building)
      "This address already belongs to building '#{existing_building.building_name}'"
    end

    def duplicate_address_message(duplicate)
      "This address is duplicated in import file (see row #{duplicate.original_data['_original_row']})"
    end
end
