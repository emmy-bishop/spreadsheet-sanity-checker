class AddUniqueIndexToPropertiesOnAddress < ActiveRecord::Migration[8.1]
  def change
    add_index :properties, [ :street_address, :city, :state, :zip_code ],
               unique: true,
               name: "index_properties_on_full_address"
  end
end
