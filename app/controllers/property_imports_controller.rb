class PropertyImportsController < ApplicationController
  before_action :set_import, only: [ :show, :preview, :execute, :destroy ]

  # ==================================================
  # INDEX
  # ==================================================
  # Purpose: Display a list of all previous imports
  # Steps:
  #   1. Fetch all imports ordered by most recent first
  #   2. Render index view with @imports collection
  def index
    @imports = PropertyImport.order(created_at: :desc)
  end

  # ==================================================
  # NEW
  # ==================================================
  # Purpose: Render the upload form for a new import
  # Steps:
  #   1. Create empty PropertyImport object for the form
  #   2. Render new view with form
  def new
    @import = PropertyImport.new
  end

  # ==================================================
  # CREATE
  # ==================================================
  # Purpose: Handle file upload, process CSV, and show preview or errors
  # Steps:
  #   1. Create new PropertyImport with form params
  #   2. Check if file was provided
  #   3. Save filename and create import record
  #   4. Process file with CsvProcessorService
  #   5. On success: redirect to preview page
  #   6. On failure: show errors and re-render upload form
  def create
    @import = PropertyImport.new(import_params)

    if params[:property_import][:filename].present?
      uploaded_file = params[:property_import][:filename]
      @import.filename = uploaded_file.original_filename

      if @import.save
        service = CsvProcessingService.new(@import, uploaded_file)

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

  # ==================================================
  # PREVIEW
  # ==================================================
  # Purpose: Show user a preview of what will be imported
  # Steps:
  #   1. Generate summary statistics from import rows
  #   2. Fetch all property rows for display
  #   3. Fetch all unit rows for display
  #   4. Render preview view with all data
  def preview
    @summary = @import.summary_stats
    @property_rows = @import.property_import_rows.property.order(:id)
    @unit_rows = @import.property_import_rows.unit.order(:id)
  end

  # ==================================================
  # EXECUTE
  # ==================================================
  # Purpose: User confirmed preview, now actually import to database
  # Steps:
  #   1. Initialize ImportTransactionService with the import
  #   2. Attempt to execute the import transaction
  #   3. On success: redirect to show page with results
  #   4. On failure: redirect back to preview with errors
  def execute
    service = ImportTransactionService.new(@import)

    if service.execute
      redirect_to property_import_path(@import)
    else
      redirect_to preview_property_import_path(@import),
                  alert: "Import failed: #{service.errors.join(', ')}"
    end
  end

  # ==================================================
  # SHOW
  # ==================================================
  # Purpose: Display results of a completed import
  # Steps:
  #   1. Generate summary statistics
  #   2. Render show view with import results
  def show
    @summary = @import.summary_stats
  end

  # ==================================================
  # DESTROY
  # ==================================================
  # Purpose: Delete an import record (admin only)
  # Note: Currently unlinked in UI - for admin use only
  # Steps:
  #   1. Delete the import record (cascades to import rows)
  #   2. Redirect to imports list with success message
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
