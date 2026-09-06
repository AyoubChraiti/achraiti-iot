# Bootstrap a short-lived API token inside our local GitLab lab.
user = User.find_by!(username: 'root')
user.personal_access_tokens.where(name: 'iot-bootstrap', revoked: false).find_each(&:revoke!)
token = user.personal_access_tokens.create!(
  name: 'iot-bootstrap', scopes: ['api'], expires_at: 7.days.from_now.to_date
)
puts token.token
