
namespace :measures do

  task :export_bundle ,[:config] do |t, args|
    config = YAML.load(args.config)
    measures = config["measures"].nil? ? Measure.all : Measure.where({hqmf_id: {"$in" => config["measures"]}})
    exporter = Measures::Exporter::BundlerExporter.new(measures,config)
    exporter.rebuild_measures if config["rebuild_measures"]
    exporter.calculate if config["rebuild_measures"] || config["calculate"]
    exporter.compress_artifiacts
  end


end