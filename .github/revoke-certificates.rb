# Revokes the development certificates Xcode created on this runner to sign the archive: each run starts with a
# keychain without one, so each upload would add one to the account, until its limit stops the uploads.
# Usage: revoke-certificates.rb <certificates of the keychain before the archive, PEM>; KEY_PATH, KEY_ID, ISSUER_ID.
require 'base64'
require 'json'
require 'net/http'
require 'openssl'

def serials(pem)
  pem.scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m).map do |text|
    OpenSSL::X509::Certificate.new(text).serial.to_s(16).upcase.sub(/\A0+/, '')
  end
end

before = File.exist?(ARGV.fetch(0)) ? serials(File.read(ARGV.fetch(0))) : []
created = serials(`security find-certificate -a -c "Apple Development" -p 2>/dev/null`) - before
if created.empty?
  puts 'No development certificate created by this run'
  exit
end

# A token of the App Store Connect API: ES256, its signature as r and s of 32 bytes each.
key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('KEY_PATH')))
b64 = ->(bytes) { Base64.urlsafe_encode64(bytes, padding: false) }
now = Time.now.to_i
input = [
  { alg: 'ES256', kid: ENV.fetch('KEY_ID'), typ: 'JWT' },
  { iss: ENV.fetch('ISSUER_ID'), iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
].map { |part| b64.call(part.to_json) }.join('.')
r, s = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest.new('SHA256'), input)).value.map do |number|
  number.value.to_s(2).rjust(32, "\0")
end
token = "#{input}.#{b64.call(r + s)}"

http = Net::HTTP.start('api.appstoreconnect.apple.com', 443, use_ssl: true)
call_api = lambda do |request|
  request['Authorization'] = "Bearer #{token}"
  http.request(request)
end
list = call_api.call(Net::HTTP::Get.new('/v1/certificates?filter%5BcertificateType%5D=DEVELOPMENT,IOS_DEVELOPMENT&limit=200'))
abort "Cannot list the certificates: #{list.code} #{list.body}" unless list.is_a?(Net::HTTPSuccess)
JSON.parse(list.body).fetch('data').each do |certificate|
  next unless created.include?(certificate.dig('attributes', 'serialNumber').to_s.upcase.sub(/\A0+/, ''))

  revoked = call_api.call(Net::HTTP::Delete.new("/v1/certificates/#{certificate.fetch('id')}"))
  abort "Cannot revoke #{certificate.fetch('id')}: #{revoked.code} #{revoked.body}" unless revoked.is_a?(Net::HTTPSuccess)
  puts "Revoked the development certificate #{certificate.fetch('id')}"
end
