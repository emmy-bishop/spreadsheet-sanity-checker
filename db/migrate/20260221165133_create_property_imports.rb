class CreatePropertyImports < ActiveRecord::Migration[8.1]
  def change
    create_table :property_imports do |t|
      t.string :filename
      t.string :status, default: "pending"
      t.jsonb :summary, default: {}
      t.jsonb :error_summary
      t.text :raw_csv_data
      t.datetime :imported_at
      t.integer :properties_created_count, default: 0
      t.integer :units_created_count, default: 0

      t.timestamps
    end

    add_index :property_imports, :status
    add_index :property_imports, :created_at
  end
end
