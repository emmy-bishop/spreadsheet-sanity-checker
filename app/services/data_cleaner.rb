module DataCleaner
  def clean_text(value)
    return nil if value.blank?
    value.to_s.strip.squeeze(" ").gsub(/[.,;:]$/, "").strip
  end

  def clean_title(value)
    return nil if value.blank?
    clean_text(value).titleize
  end

  # Specific cleaners using the generic ones
  def clean_street_address(value) = clean_text(value)
  def clean_city(value) = clean_title(value)
  def clean_state(value) = value.to_s.strip.titleize
  def clean_building_name(value) = clean_text(value).gsub(/\s+(Apt|Unit|#).*$/i, "")
                                                    # allow spaces but remove punctuation
                                                    .gsub(/[.,;:]/, "")
                                                    .strip

  def clean_unit_number(value)
    return nil if value.blank?
    value.to_s.strip
         .gsub(/\.0+$/, "") # Excel numbers import as floats, so remove any .0s
         .gsub(/^0+/, "") # No leading zeros
         .gsub(/\s*(apt|unit|#|apartment|suite)\s*/i, "") # No "apt/unit/#"/etc
         .gsub(/[^\w-]/, "") # No punctuation (except hyphens/underscores)
         .gsub(/-+/, "-") # Collapse multiple consecutive hyphens
         .gsub(/^-|-$/, "") # No leading/trailing hyphens
  end

  def clean_zip_code(value)
    return nil if value.blank?
    value.to_s
         .strip
         .gsub(/\.0+$/, "") # Excel numbers import as floats, so remove any .0s
         .gsub(/[^0-9]/, "") # Only allow digits
         .then { |z| z[0..4] }
  end
end
