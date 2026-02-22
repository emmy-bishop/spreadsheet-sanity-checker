class CreateUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :units do |t|
      t.references :property, null: false, foreign_key: { on_delete: :cascade }
      t.string :unit_number, null: false

      t.timestamps
    end

    add_index :units, [ :property_id, :unit_number ], unique: true
  end
end
