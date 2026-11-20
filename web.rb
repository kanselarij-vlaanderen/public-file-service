require 'ruby-filemagic'
require 'fileutils'

###
# Configuration
###

if ENV['MU_APPLICATION_FILE_STORAGE_PATH'] and ENV['MU_APPLICATION_FILE_STORAGE_PATH'].start_with?('/')
  Mu::log.fatal "MU_APPLICATION_FILE_STORAGE_PATH (#{ENV['MU_APPLICATION_FILE_STORAGE_PATH']}) must be relative"
  exit
else
  FileUtils.mkdir_p "/share/#{ENV['MU_APPLICATION_FILE_STORAGE_PATH']}"
end

configure do
  set :relative_storage_path, (ENV['MU_APPLICATION_FILE_STORAGE_PATH'] || '').chomp('/')
  set :storage_path, "/share/#{(ENV['MU_APPLICATION_FILE_STORAGE_PATH'] || '')}".chomp('/')
  set :file_resource_base, (ENV['FILE_RESOURCE_BASE'] || '')
end

file_magic = FileMagic.new(FileMagic::MAGIC_MIME)


###
# Vocabularies
###
DC = RDF::Vocab::DC
NFO = RDF::Vocabulary.new('http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#')
NIE = RDF::Vocabulary.new('http://www.semanticdesktop.org/ontologies/2007/01/19/nie#')
DBPEDIA = RDF::Vocabulary.new('http://dbpedia.org/ontology/')
BESLUITVORMING = RDF::Vocabulary.new('https://data.vlaanderen.be/ns/besluitvorming#')
PROV = RDF::Vocabulary.new('http://www.w3.org/ns/prov#')


###
# GET /files/:id
# Get metadata of the file with the given id
#
# Returns 200 containing the file with the specified id
#         404 if a file with the given id cannot be found
###
get '/files/:id' do
  rewrite_url = Mu::Helpers::rewrite_url_header(request)
  error('X-Rewrite-URL header is missing.') if rewrite_url.nil?

  query = " SELECT ?uri ?name ?format ?size ?extension WHERE {"
  query += "   GRAPH <#{ENV['SPECIFIED_GRAPH']}> {" if ENV['SPECIFIED_GRAPH']
  query += "   ?uri <#{MU_CORE.uuid}> #{Mu::sparql_escape_string(params['id'])} ;"
  query += "        <#{NFO.fileName}> ?name ;"
  query += "        <#{DC.format}> ?format ;"
  query += "        <#{DBPEDIA.fileExtension}> ?extension ;"
  query += "        <#{NFO.fileSize}> ?size ."
  unless ENV['SKIP_CONFIDENTIALITY']
    query += "   ?document <#{PROV.value}> ?uri."
    query += "   ?document <#{BESLUITVORMING.vertrouwelijkheidsniveau}> <http://themis.vlaanderen.be/id/concept/toegangsniveau/c3de9c70-391e-4031-a85e-4b03433d6266>."
  end
  query += "   }" if ENV['SPECIFIED_GRAPH']
  query += " }"
  result = Mu::query(query, sudo: true)

  return status 404 if result.empty?
  result = result.first

  content_type 'application/vnd.api+json'
  status 200
  {
    data: {
      type: 'files',
      id: params['id'],
      attributes: {
        name: result[:name].value,
        format: result[:format].value,
        size: result[:size].value,
        extension: result[:extension].value
      }
    },
    links: {
      self: rewrite_url
    }
  }.to_json
end

###
# GET /files/:id/download?name=foo.pdf
#
# @param name [string] Optional name of the downloaded file
# @param content-disposition [string] Optional Content-Disposition header value, 'inline' or 'attachment' (default)
#
# Returns 200 with the file content as attachment
#         404 if a file with the given id cannot be found
#         500 if the file is available in the database but not on disk
###
get '/files/:id/download' do
  query = " SELECT ?fileUrl WHERE {"
  query += "   GRAPH <#{ENV['SPECIFIED_GRAPH']}> {" if ENV['SPECIFIED_GRAPH']
  query += "   ?uri <#{MU_CORE.uuid}> #{Mu::sparql_escape_string(params['id'])} ."
  query += "   ?fileUrl <#{NIE.dataSource}> ?uri ."
  unless ENV['SKIP_CONFIDENTIALITY']
    query += "   ?document <#{PROV.value}> ?uri."
    query += "   ?document <#{BESLUITVORMING.vertrouwelijkheidsniveau}> <http://themis.vlaanderen.be/id/concept/toegangsniveau/c3de9c70-391e-4031-a85e-4b03433d6266>."
  end
  query += "   }" if ENV['SPECIFIED_GRAPH']
  query += " }"
  result = Mu::query(query, sudo: true)

  return status 404 if result.empty?

  url = result.first[:fileUrl].value
  path = shared_uri_to_path(url)

  filename = params['name']
  filename ||= File.basename(path)

  if params['content-disposition'] and params['content-disposition'].casecmp? 'inline'
    disposition = 'inline'
  else
    disposition = 'attachment'
  end

  if File.file?(path)
    send_file path, disposition: disposition, filename: filename
  else
    Mu::Helpers::error("Could not find file in path. Check if the physical file is available on the server and if this service has the right mountpoint.", 500)
  end
end

###
# Helpers
###
def shared_uri_to_path(uri)
  uri.sub('share://', '/share/')
end

def file_to_shared_uri(file_name)
  if settings.relative_storage_path and not settings.relative_storage_path.empty?
    return "share://#{settings.relative_storage_path}/#{file_name}"
  else
    return "share://#{file_name}"
  end
end
