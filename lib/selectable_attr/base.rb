# -*- coding: utf-8 -*-
module SelectableAttr
  module Base
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    ENUM_ARRAY_METHODS = {
      :none => { 
        :to_hash_array => Proc.new do |enum, attr_value|
          value = (attr_value || []).map(&:to_s)
          enum.to_hash_array do |hash|
            hash[:select] = value.include?(hash[:id].to_s)
          end
        end,
        
        :to_attr_value => Proc.new do |enum, hash_array|
          hash_array.select{|hash| hash[:select]}.map{|hash| hash[:id]}
        end
      },
      
      :comma_string => {
        :to_hash_array => Proc.new do |enum, attr_value|
          values = attr_value.is_a?(Array) ? attr_value.map{|v|v.to_s} :
            (attr_value || '').split(',')
          enum.to_hash_array do |hash|
            hash[:select] = values.include?(hash[:id].to_s)
          end
        end,
        
        :to_attr_value => Proc.new do |enum, hash_array|
          hash_array.select{|hash| hash[:select]}.map{|hash| hash[:id]}.join(',')
        end
      },
      
      
      :binary_string => {
        :to_hash_array => Proc.new do |enum, attr_value|
          value = attr_value || ''
          idx = 0
          enum.to_hash_array do |hash|
            hash[:select] = (value[idx, 1] == '1')
            idx += 1
          end
        end,
        
        :to_attr_value => Proc.new do |enum, hash_array|
          result = ''
          hash_map = hash_array.inject({}){|dest, hash| dest[hash[:id]] = hash; dest}
          enum.each do |entry|
            hash = hash_map[entry.id]
            result << (hash[:select] ? '1' : '0')
          end
          result
        end
      }
    }
    
    module ClassMethods
      def enum(*args, &block)
        process_definition(block, *args) do |enum, context|
          define_enum_class_methods(context)
          define_enum_instance_methods(context)
        end
      end
      alias_method :single_selectable_attr, :enum
      alias_method :selectable_attr, :enum
      
      
      def enum_array(*args, &block)
        base_options = args.extract_options! # last.is_a?(Hash) ? args.pop : {}
        args << base_options # .update({:attr_accessor => false})
        process_definition(block, *args) do |enum, context|
          define_enum_class_methods(context)
          define_enum_array_instance_methods(context)
        end
      end
      alias_method :multi_selectable_attr, :enum_array
      
      def process_definition(block, *args)
        base_options = args.extract_options! # last.is_a?(Hash) ? args.pop : {}
        enum = base_options[:enum] || create_enum(&block)
        args.each do |attr|
          context = {
            :enum => enum,
            :attr_accessor => !has_attr(attr),
            :attr => attr,
            :base_name => enum_base_name(attr)
          }.update(base_options)
          define_enum(context)
          define_accessor(context)
          yield(enum, context)
        end
        enum
      end
      
      def has_attr(attr)
        return true if self.method_defined?(attr)
        return false unless self.respond_to?(:columns)
        (self.columns || []).any?{|col|col.name.to_s == attr.to_s}
      end
      
      def attr_enumeable_base(*args, &block)
        @base_name_processor = block
      end
      
      def enum_base_name(attr)
        if @base_name_processor
          @base_name_processor.call(attr).to_s
        else
          attr.to_s.gsub(/(_cd$|_code$|_cds$|_codes$)/, '')
        end
      end
      
      def create_enum(&block)
        result = Enum.new
        result.instance_eval(&block)
        result
      end
      
      def define_enum(context)
        base_name = context[:base_name]
        const_set("#{base_name.upcase}_ENUM", context[:enum])
      end
      
      def enum_for(attr)
        base_name = enum_base_name(attr)
        const_get("#{base_name.upcase}_ENUM")
      end
      
      def define_accessor(context)
        attr = context[:attr]
        if context[:attr_accessor]
          if context[:default]
            attr_accessor_with_default(attr, context[:default])
          else
            attr_accessor(attr)
          end
        else
          if context[:default]
            $stderr.puts "WARNING! :default option ignored for #{attr}"
          end
        end
      end
      
      def define_enum_class_methods(context)
        base_name = context[:base_name]
        enum = context[:enum]
        mod = Module.new
        mod.module_eval do
          define_method("#{base_name}_enum"){enum}
          define_method("#{base_name}_hash_array"){enum.to_hash_array}
          define_method("#{base_name}_entries"){enum.entries}
          define_method("#{base_name}_options"){|*ids_or_keys|enum.options(*ids_or_keys)}
          define_method("#{base_name}_ids"){|*ids_or_keys| enum.ids(*ids_or_keys)}
          define_method("#{base_name}_keys"){|*ids_or_keys|enum.keys(*ids_or_keys)}
          define_method("#{base_name}_names"){|*ids_or_keys|enum.names(*ids_or_keys)}
          define_method("#{base_name}_key_by_id"){|id|enum.key_by_id(id)}
          define_method("#{base_name}_id_by_key"){|key|enum.id_by_key(key)}
          define_method("#{base_name}_name_by_id"){|id|enum.name_by_id(id)}
          define_method("#{base_name}_name_by_key"){|key|enum.name_by_key(key)}
          define_method("#{base_name}_entry_by_id"){|id|enum.entry_by_id(id)}
          define_method("#{base_name}_entry_by_key"){|key|enum.entry_by_key(key)}
        end
        if convertors = ENUM_ARRAY_METHODS[context[:convert_with] || :none]
          mod.module_eval do
            define_method("#{base_name}_to_hash_array", convertors[:to_hash_array])
            define_method("hash_array_to_#{base_name}", convertors[:to_attr_value])
          end
        end
        self.extend(mod)
      end
      
      def define_enum_instance_methods(context)
        attr = context[:attr]
        base_name = context[:base_name]
        instance_methods = <<-EOS
          def #{base_name}_key
            self.class.#{base_name}_key_by_id(#{attr})
          end
          def #{base_name}_key=(key)
            self.#{attr} = self.class.#{base_name}_id_by_key(key)
          end
          def #{base_name}_name
            self.class.#{base_name}_name_by_id(#{attr})
          end
          def #{base_name}_entry
            self.class.#{base_name}_entry_by_id(#{attr})
          end
          def #{base_name}_entry
            self.class.#{base_name}_entry_by_id(#{attr})
          end
        EOS
        self.module_eval(instance_methods)
      end
        
      def define_enum_array_instance_methods(context)
        attr = context[:attr]
        base_name = context[:base_name]
        # ActiveRecord::Baseから継承している場合は、基本カラムに対応するメソッドはない
        self.module_eval(<<-"EOS")
          def #{base_name}_ids
            #{base_name}_hash_array_selected.map{|hash|hash[:id]}
          end
          def #{base_name}_ids=(ids)
            ids = ids.split(',') if ids.is_a?(String)
            ids = ids ? ids.map(&:to_s) : []
            update_#{base_name}_hash_array{|hash|ids.include?(hash[:id].to_s)}
          end
        EOS
        self.module_eval(<<-"EOS")
          def #{base_name}_hash_array
            self.class.#{base_name}_to_hash_array(self.class.#{base_name}_enum, #{attr})
          end
          def #{base_name}_hash_array=(hash_array)
            self.#{attr} = self.class.hash_array_to_#{base_name}(self.class.#{base_name}_enum, hash_array)
          end
          def #{base_name}_hash_array_selected
            #{base_name}_hash_array.select{|hash|!!hash[:select]}
          end
          def update_#{base_name}_hash_array(&block)
            hash_array = #{base_name}_hash_array.map do |hash|
              hash.merge(:select => yield(hash))
            end
            self.#{base_name}_hash_array = hash_array
          end
          def #{base_name}_keys
            #{base_name}_hash_array_selected.map{|hash|hash[:key]}
          end
          def #{base_name}_keys=(keys)
            update_#{base_name}_hash_array{|hash|keys.include?(hash[:key])}
          end
          def #{base_name}_selection
            #{base_name}_hash_array.map{|hash|!!hash[:select]}
          end
          def #{base_name}_selection=(selection)
            idx = -1
            update_#{base_name}_hash_array{|hash| idx += 1; !!selection[idx]}
          end
          def #{base_name}_names
            #{base_name}_hash_array_selected.map{|hash|hash[:name]}
          end
          def #{base_name}_entries
            ids = #{base_name}_ids
            self.class.#{base_name}_enum.select{|entry|ids.include?(entry.id)}
          end
        EOS
      end
    end
  end
end
