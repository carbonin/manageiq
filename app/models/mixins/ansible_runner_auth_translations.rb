module AnsibleRunnerAuthTranslations
  AUTH_TYPES = %i[credential vault_credential cloud_credential network_credential]

  module_function

  # Translates options hash with credential_ids into auth
  #
  # @param [Hash] options Hash containing the credential_ids
  # @param [Hash] other_hash (options) Data to be updated if differs from <options>
  # @param [Boolean] mutate_options (false) If passed in option keys should be removed, set to true
  #
  def translate_credentials!(options, other_hash: nil, mutate_options: false)
    other_hash ||= options

    AUTH_TYPES.each do |credential|
      credential_sym         = "#{credential}_id".to_sym
      credential_id          = mutate_options ? options.delete(credential_sym) : options[credential_sym]
      other_hash[credential] = Authentication.find(credential_id).native_ref if credential_id.present?
    end
  end
end
