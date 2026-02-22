class CreatePropertyImportRows < ActiveRecord::Migration[8.1]
  def change
    create_table :property_import_rows do |t|
      t.references :property_import, null: false, foreign_key: { on_delete: :cascade }
      t.string :record_type, null: false
      t.jsonb :original_data, null: false, default: {}
      t.jsonb :parsed_data, null: false, default: {}
      t.string :status, default: "pending"
      t.text :validation_errors
      t.references :existing_property, foreign_key: { to_table: :properties }
      t.references :created_property, foreign_key: { to_table: :properties }

      t.timestamps
    end

    add_index :property_import_rows, :status
    add_index :property_import_rows, :record_type
    add_index :property_import_rows, [ :property_import_id, :status ]
    add_index :property_import_rows, [ :property_import_id, :record_type ]
  end
end
