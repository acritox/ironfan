#!/usr/bin/env ruby

require 'configliere'
require 'extlib/mash'
require 'gorillib/metaprogramming/class_attribute'
require 'gorillib/hash/reverse_merge'
require 'gorillib/object/blank'
require 'gorillib/hash/compact'
require 'set'

require 'erubis'
require 'chef/mixin/from_file'

$:.unshift File.expand_path('..', File.dirname(__FILE__))
require 'cluster_chef/dsl_object'


Settings.define :author,           :default => "Philip (flip) Kromer"
Settings.define :maintainer,       :default => "Infochimps, Inc"
Settings.define :maintainer_email, :default => "coders@infochimps.org"
Settings.define :license,          :default => "Apache 2.0"
Settings.define :long_desc_gen,    :default => %Q{IO.read(File.join(File.dirname(__FILE__), 'README.md'))}
Settings.define :version,          :default => "3.0.0"
Settings.define :supports,         :default => %w[debian ubuntu]


module CookbookMunger
  TEMPLATE_ROOT  = File.expand_path('cookbook_munger', File.dirname(__FILE__))
  COOKBOOKS_ROOT = File.expand_path('../..', File.dirname(__FILE__))

  class DummyAttribute
    attr_accessor :name
    attr_accessor :display_name
    attr_accessor :description
    attr_accessor :default
    attr_accessor :type

    def initialize(name, opts={})
      self.name = name
      opts.each do |key, val|
        self.send("#{key}=", val)
      end
    end

    def inspect
      "attr[#{name}:#{default.inspect}]"
    end

    def bracketed_name
      name.split("/").map{|s| "[:#{s}]" }.join
    end

    def to_hash
      {
        :display_name => display_name,
        :description  => description,
        :default      => default,
        :type         => type,
      }
    end

    def pretty_str
      str = [ %Q{attribute "#{name}"} ]
      to_hash.each do |key, val|
        next if val.blank? && [:default, :type].include?(key)
        str << ("  :%-21s => %s" % [ key, val.inspect ])
      end
      str.flatten.join(",\n")
    end
  end

  class DummyAttributeCollection < Mash
    attr_accessor :path

    def initialize(path='')
      self.path = path
      super(){|hsh,key| hsh[key] = DummyAttributeCollection.new(sub_path(key)) }
    end

    def setter(key=nil)
      # key ? (self[key] = DummyAttributeCollection.new(sub_path(key))) : self
      self
    end

    def sub_path(key)
      path.blank? ? key.to_s : "#{path}/#{key}"
    end

    def []=(key, val)
      unless val.is_a?(DummyAttributeCollection) || val.is_a?(DummyAttribute)
        val = DummyAttribute.new(sub_path(key), :default =>val)
      end
      super(key, val)
    end

    def attrs
      [ leafs.values, branches.map{|key,val| val.attrs } ].flatten
    end

    def leafs
      select{|key,val| not val.is_a?(DummyAttributeCollection) }
    end
    def branches
      select{|key,val|     val.is_a?(DummyAttributeCollection) }
    end

    def pretty_str
      str = []
      attrs.each{|attrib| str << attrib.pretty_str }
      str.join("\n\n")
    end

  end

  class AttributeFile < ClusterChef::DslObject
    include       Chef::Mixin::FromFile
    attr_reader   :all_attributes, :filename

    def initialize(filename)
      @all_attributes = DummyAttributeCollection.new
      @filename = filename
    end

    def default
      all_attributes
    end

    def read!
      from_file(filename)
    end
  end

  class MetadataFile < ClusterChef::DslObject
    include       Chef::Mixin::FromFile
    has_keys      :author, :maintainer, :maintainer_email, :license, :version, :description, :long_desc_gen
    attr_reader   :all_depends, :all_recipes, :all_attributes, :all_resources, :all_supports

    def initialize(*args, &block)
      super(*args, &block)
      @attribute_files  = []
      @all_attributes   = CookbookMunger::DummyAttributeCollection.new
      @all_depends    ||= {}
      @all_recipes    ||= {}
      @all_resources  ||= {}
      @all_supports   ||= []
    end

    #
    # Fake DSL
    #

    # add dependency to list
    def depends(nm, ver=nil)  @all_depends[nm] = (ver ? %Q{"#{nm}", "#{ver}"} : %Q{"#{nm}"} ) ; end
    # add supported OS to list
    def supports(nm)          @all_supports << nm ;     end
    # add recipe to list
    def recipe(nm, desc)      @all_recipes[nm] = { :name => nm, :description => desc } ;   end
    # add resource to list
    def resource(nm, desc)    @all_resources[nm] = { :name => nm, :description => desc } ;   end
    # fake long description -- we ignore it anyway
    def long_description(val) @long_description = val end

    # add attribute to list
    def attribute(nm, info)
      path_segs = nm.split("/")
      leaf      = path_segs.pop
      attr_branch = @all_attributes
      path_segs.each{|seg| attr_branch = attr_branch[seg] }
      attr_branch[leaf] = CookbookMunger::DummyAttribute.new(nm, info)
    end

    def add_attribute_file(filename)
      attr_file = CookbookMunger::AttributeFile.new(filename)
      attr_file.read!
      attribute_files << attr_file
    end

    #
    # Content
    #

    def self.licenses
      return @licenses if @licenses
      @licenses = YAML.load(self.load_template_file('licenses.yaml'))
    end

    def license_info
      @license_info ||= self.class.licenses.values.detect{|lic| lic[:name] == license }
    end

    def short_license_text
      license_info[:short]
    end

    def copyright_text
      "2011, #{maintainer}"
    end

    #
    # Display
    #

    def to_hash
      super.merge({
          :all_depends    => all_depends,
          :all_recipes    => all_recipes,
          :all_attributes => all_attributes,
          :all_supports   => all_supports,
        })
    end

    def render
      self.class.template.result(self.send(:binding))
    end

    def self.load_template_file(filename)
      File.read(File.expand_path(filename, CookbookMunger::TEMPLATE_ROOT))
    end

    def self.template
      return @template if @template
      # template_text = load_template_file('metadata.rb.erb')
      template_text   = load_template_file('README.md.erb')
      @template = Erubis::Eruby.new(template_text)
    end
  end

  metadata_file = MetadataFile.new(Settings.merge(
      :description => 'hi'
      ))

  metadata_file.from_file( File.expand_path('site-cookbooks/zenoss/metadata.rb', CookbookMunger::COOKBOOKS_ROOT))

  puts metadata_file.render

  # attr_file = CookbookMunger::AttributeFile.new(File.expand_path('site-cookbooks/pig/attributes/default.rb', CookbookMunger::COOKBOOKS_ROOT))
  # attr_file.read!
  # puts attr_file.all_attributes.pretty_str

  # p metadata_file.all_attributes
  # puts Time.now
end
