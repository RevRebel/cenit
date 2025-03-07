module Setup
  class CenitDataType < DataType

    origins :cenit, -> { ::User.super_access? ? [:admin, :tmp] : nil }

    default_origin :tmp

    build_in_data_type.referenced_by(:namespace, :name).with(
      :namespace,
      :name,
      :title,
      :_type,
      :snippet
    )
    build_in_data_type.and(
      properties: {
        schema: {
          type: 'object'
        }
      }
    )

    def validates_for_destroy
      if ::User.super_access?
        unless origin == :tmp || (build_in_dt = build_in).nil?
          errors.add(:base, "#{custom_title} can not be destroyed because model #{build_in_dt.model} is present.")
        end
      else
        errors.add(:base, 'You are not authorized to execute this action.')
      end
      errors.blank?
    end

    def do_configure_when_save?
      !new_record? && !::User.super_access?
    end

    def attribute_writable?(name)
      ((name == 'name') && ::User.super_access?) || super
    end

    def data_type_name
      if namespace.present?
        "#{namespace}::#{name}"
      else
        name
      end
    end

    def build_in
      Setup::BuildInDataType[data_type_name]
    end

    def find_data_type(ref, ns = namespace)
      super || build_in.find_data_type(ref, ns)
    end

    delegate :title, :schema, :subtype?, to: :build_in, allow_nil: true

    def data_type_storage_collection_name
      if (model = records_model).is_a?(Class)
        model = model.mongoid_root_class
      end
      Account.tenant_collection_name(model)
    end

    def method_missing(symbol, *args)
      if build_in.respond_to?(symbol)
        build_in.send(symbol, *args)
      else
        super
      end
    end

    def tracing?
      false
    end

    def tenant_version
      self
    end

    def slug
      if (m = build_in) && (m = m.model)
        m.to_s.split('::').last.underscore
      else
        super
      end
    end

    class << self

      def init!
        do_configure = where(origin: :cenit).empty?

        Setup::BuildInDataType.each { |dt| dt.db_data_type(true) }

        right_data_types_ids = Hash.new { |h, k| h[k] = [] }
        wrong_data_types = []
        all.each do |data_type|
          if data_type.build_in
            right_data_types_ids[data_type.build_in.origin_config || :cenit] << data_type.id if do_configure
          else
            wrong_data_types << "#{data_type.namespace}::#{data_type.name}"
          end
        end

        if do_configure
          right_data_types_ids.each do |origin, ids|
            where(:id.in => ids).cross(origin)
          end
        end

        unless wrong_data_types.empty?
          Setup::SystemReport.create(type: :warning, message: "Wrong cenit data types: #{wrong_data_types.to_sentence}")
        end
      end
    end

  end
end
