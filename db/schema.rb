# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_21_185131) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "properties", force: :cascade do |t|
    t.string "building_name", null: false
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.string "property_type", null: false
    t.string "state", null: false
    t.string "street_address", null: false
    t.datetime "updated_at", null: false
    t.string "zip_code", null: false
    t.index ["building_name"], name: "index_properties_on_building_name", unique: true
  end

  create_table "property_import_rows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_property_id"
    t.bigint "existing_property_id"
    t.jsonb "original_data", default: {}, null: false
    t.jsonb "parsed_data", default: {}, null: false
    t.bigint "property_import_id", null: false
    t.string "record_type", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.text "validation_errors"
    t.index ["created_property_id"], name: "index_property_import_rows_on_created_property_id"
    t.index ["existing_property_id"], name: "index_property_import_rows_on_existing_property_id"
    t.index ["property_import_id", "record_type"], name: "idx_on_property_import_id_record_type_aa5178ce17"
    t.index ["property_import_id", "status"], name: "index_property_import_rows_on_property_import_id_and_status"
    t.index ["property_import_id"], name: "index_property_import_rows_on_property_import_id"
    t.index ["record_type"], name: "index_property_import_rows_on_record_type"
    t.index ["status"], name: "index_property_import_rows_on_status"
  end

  create_table "property_imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "error_summary"
    t.string "filename"
    t.datetime "imported_at"
    t.integer "properties_created_count", default: 0
    t.string "status", default: "pending"
    t.jsonb "summary", default: {}
    t.integer "units_created_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_property_imports_on_created_at"
    t.index ["status"], name: "index_property_imports_on_status"
  end

  create_table "units", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "property_id", null: false
    t.string "unit_number", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id", "unit_number"], name: "index_units_on_property_id_and_unit_number", unique: true
    t.index ["property_id"], name: "index_units_on_property_id"
  end

  add_foreign_key "property_import_rows", "properties", column: "created_property_id"
  add_foreign_key "property_import_rows", "properties", column: "existing_property_id"
  add_foreign_key "property_import_rows", "property_imports", on_delete: :cascade
  add_foreign_key "units", "properties", on_delete: :cascade
end
