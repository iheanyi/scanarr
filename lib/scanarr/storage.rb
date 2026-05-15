module Scanarr
  module Storage
    module_function

    def root
      Pathname.new(
        ENV.fetch("SCANARR_STORAGE_ROOT") do
          ENV.fetch("ACTIVE_STORAGE_LOCAL_ROOT", Rails.root.join("storage").to_s)
        end
      )
    end

    def backup_root
      Pathname.new(ENV.fetch("SCANARR_BACKUP_ROOT", root.join("backups").to_s))
    end
  end
end
