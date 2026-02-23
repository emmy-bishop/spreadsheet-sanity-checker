module ImportConfig
  # This module defines the headers used in the import process
  module Headers
    BUILDING_NAME = "Building Name".freeze
    STREET_ADDRESS = "Street Address".freeze
    UNIT = "Unit".freeze
    CITY = "City".freeze
    STATE = "State".freeze
    ZIP_CODE = "Zip Code".freeze

    ALL = [ BUILDING_NAME, STREET_ADDRESS, UNIT, CITY, STATE, ZIP_CODE ].freeze

    MAPPINGS = {
      building_name: BUILDING_NAME,
      street_address: STREET_ADDRESS,
      unit: UNIT,
      city: CITY,
      state: STATE,
      zip_code: ZIP_CODE
    }.freeze
  end

  # This module defines the keys used in the parsed data
  module ParsedKeys
    BUILDING_NAME = "building_name".freeze
    STREET_ADDRESS = "street_address".freeze
    UNIT_NUMBER = "unit_number".freeze
    CITY = "city".freeze
    STATE = "state".freeze
    ZIP_CODE = "zip_code".freeze

    ALL = [ BUILDING_NAME, STREET_ADDRESS, UNIT_NUMBER, CITY, STATE, ZIP_CODE ].freeze
  end
end
