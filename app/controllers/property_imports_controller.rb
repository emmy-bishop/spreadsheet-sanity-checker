class PropertyImportsController < ApplicationController
  before_action :set_import, only: [ :show, :preview, :execute, :destroy ]

  def index
    @imports = PropertyImport.order(created_at: :desc)
  end

  def new
    # Create new PropertyImport (to be populated with spreadsheet values)
    @import = PropertyImport.new
  end

  def create
    # User submitted spreadsheet, populate PropertyImport with values from file
    @import = PropertyImport.new(import_params)

    # Handle file upload
    if params[:property_import][:filename].present?
      uploaded_file = params[:property_import][:filename]
      @import.filename = uploaded_file.original_filename

      # Save the import first
      if @import.save
        # Pass the uploaded file for processing
        service = CsvProcessorService.new(@import, uploaded_file)

        # On success, redirect to preview
        if service.process
          redirect_to preview_property_import_path(@import)
        else
          @import.update(status: :failed, error_summary: { errors: service.errors })
          flash.now[:alert] = "Error processing file: #{service.errors.join(', ')}"
          render :new, status: :unprocessable_entity
        end
      else
        render :new, status: :unprocessable_entity
      end
    else
      @import.errors.add(:filename, "must be provided")
      render :new, status: :unprocessable_entity
    end
  end

  def preview
    # Processing succeeded -- show preview of data to be imported w/ stats
    @summary = @import.summary_stats
    # as well as lists of unique properties & unique units
    @property_rows = @import.property_import_rows.property.order(:id)
    @unit_rows = @import.property_import_rows.unit.order(:id)
  end

  def execute
    # User previewed import, found no validation errors, and hit submit
    # So start adding finalized db records
    service = ImportTransactionService.new(@import)

    # On success, redirect to import summary page
    if service.execute
      redirect_to property_import_path(@import)
    else
      redirect_to preview_property_import_path(@import),
                  alert: "Import failed: #{service.errors.join(', ')}"
    end
  end

  def show
    @summary = @import.summary_stats
  end

  # This is currently unlinked in the UI because it should only be accessible to admin users,
  # but could allow for deleting an import record if needed
  # (e.g. if they want to re-upload a file with the same name)
  def destroy
    @import.destroy
    redirect_to property_imports_path, notice: "Import record deleted"
  end

  private

    def set_import
      @import = PropertyImport.find(params[:id])
    end

    def import_params
      # Filename is a nested attribute, so we need to explicitly permit it
      params.require(:property_import).permit(:filename)
    end
end
