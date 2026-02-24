module DataCleaner
  def clean_text(value)
    return nil if value.blank?
    value.to_s
         .strip
         .squeeze(" ")
         .gsub(/[.,;:]$/, "")
         .strip
  end

  def clean_title(value)
    return nil if value.blank?
    clean_text(value)&.titleize
  end

  # Specific cleaners using the generic ones
  def clean_street_address(value)
    return nil if value.blank?
    clean_text(value)
  end

  def clean_city(value)
    return nil if value.blank?
    clean_title(value)
  end

  def clean_state(value)
    return nil if value.blank?
    value.to_s.strip.titleize
  end

  def clean_building_name(value)
    return nil if value.blank?
    
    clean_text(value)
      .to_s
      .gsub(/\s+(Apt|Unit|#).*$/i, "")
      .gsub(/[.,;:]/, "")
      .strip
  end

  def clean_unit_number(value)
    return nil if value.blank?
    
    value.to_s
         .strip
         .gsub(/\.0+$/, "") # Remove .0 from Excel numbers
         .gsub(/^0+/, "") # Remove leading zeros
         .gsub(/\s*(apt|unit|#|apartment|suite)\s*/i, "") # Remove prefixes
         .gsub(/[^\w-]/, "") # Keep only letters, numbers, hyphens, underscores
         .gsub(/-+/, "-") # Collapse multiple hyphens
         .gsub(/^-|-$/, "") # Remove leading/trailing hyphens
  end

  def clean_zip_code(value)
    return nil if value.blank?
    
    value.to_s
         .strip
         .gsub(/\.0+$/, "") # Remove .0 from Excel numbers
         .gsub(/[^0-9]/, "") # Keep only digits
         .then { |z| z[0..4] } # Keep only the first 5 digits
  end
end