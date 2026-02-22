class RemoveRawCsvDataFromPropertyImports < ActiveRecord::Migration[8.1]
  def change
    remove_column :property_imports, :raw_csv_data, :text
  end
end
