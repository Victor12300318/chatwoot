# Serviço provedor para integração WhatsApp via Gupshup BSP
# Documentação da API: https://docs.gupshup.io/docs/whatsapp-api-documentation
#
# Configuração necessária no provider_config:
#   - api_key: Chave de API do Gupshup
#   - app_name: Nome do aplicativo no Gupshup
#
class Whatsapp::Providers::GupshupService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_payload = build_template_payload(template_info)

    response = HTTParty.post(
      "#{api_base_path}/template/msg",
      headers: api_headers,
      body: {
        channel: 'whatsapp',
        source: source_phone,
        destination: format_destination(phone_number),
        template: template_payload
      }.to_json
    )

    process_gupshup_response(response, message)
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated

    response = HTTParty.get(
      "#{api_base_path}/template/list/#{whatsapp_channel.provider_config['app_name']}",
      headers: api_headers
    )

    return unless response.success?

    templates = transform_gupshup_templates(response['templates'] || [])
    whatsapp_channel.update(
      message_templates: templates,
      message_templates_last_updated: Time.now.utc
    )
  end

  def validate_provider_config?
    return false if whatsapp_channel.provider_config['api_key'].blank?
    return false if whatsapp_channel.provider_config['app_name'].blank?

    response = HTTParty.get(
      "#{api_base_path}/app/#{whatsapp_channel.provider_config['app_name']}",
      headers: api_headers
    )

    response.success?
  end

  def api_headers
    {
      'apikey' => whatsapp_channel.provider_config['api_key'],
      'Content-Type' => 'application/json'
    }
  end

  def media_url(media_id)
    "#{api_base_path}/media/#{media_id}"
  end

  private

  def api_base_path
    ENV.fetch('GUPSHUP_BASE_URL', 'https://api.gupshup.io/sm/api/v1')
  end

  def source_phone
    whatsapp_channel.phone_number.delete('+')
  end

  def format_destination(phone_number)
    phone_number.to_s.delete('+')
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{api_base_path}/msg",
      headers: api_headers,
      body: {
        channel: 'whatsapp',
        source: source_phone,
        destination: format_destination(phone_number),
        message: {
          type: 'text',
          text: message.outgoing_content
        }
      }.to_json
    )

    process_gupshup_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = determine_attachment_type(attachment.file_type)
    type_content = build_attachment_content(type, attachment, message)

    response = HTTParty.post(
      "#{api_base_path}/msg",
      headers: api_headers,
      body: {
        channel: 'whatsapp',
        source: source_phone,
        destination: format_destination(phone_number),
        message: {
          type: type,
          type.to_s => type_content
        }
      }.to_json
    )

    process_gupshup_response(response, message)
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{api_base_path}/msg",
      headers: api_headers,
      body: {
        channel: 'whatsapp',
        source: source_phone,
        destination: format_destination(phone_number),
        message: {
          type: 'interactive',
          interactive: payload
        }
      }.to_json
    )

    process_gupshup_response(response, message)
  end

  def determine_attachment_type(file_type)
    return file_type if %w[image audio video].include?(file_type)

    'document'
  end

  def build_attachment_content(type, attachment, message)
    content = { link: attachment.download_url }

    unless %w[audio sticker].include?(type)
      content[:caption] = message.outgoing_content
    end

    if type == 'document'
      content[:filename] = attachment.file.filename if attachment.file&.filename
    end

    content
  end

  def build_template_payload(template_info)
    payload = {
      id: template_info[:template_id] || template_info[:name],
      params: extract_template_params(template_info)
    }

    # Adiciona código do idioma se especificado
    if template_info[:lang_code].present?
      payload[:language] = { code: template_info[:lang_code], policy: 'deterministic' }
    end

    payload
  end

  def extract_template_params(template_info)
    params = template_info[:parameters] || []

    # Se os parâmetros estão no formato de componentes do WhatsApp Cloud
    if params.is_a?(Array) && params.any? { |p| p.is_a?(Hash) && p[:type].present? }
      # Extrai apenas os valores de texto dos componentes body
      body_component = params.find { |p| p[:type] == 'body' }
      return body_component&.dig(:parameters)&.map { |p| p[:text] }&.compact || []
    end

    # Formato simples: array de strings
    params.map { |p| p[:text] || p.to_s }
  end

  def transform_gupshup_templates(templates)
    templates.map do |template|
      {
        'name' => template['elementName'] || template['name'],
        'namespace' => template['namespace'],
        'language' => template['languageCode'] || template['language'],
        'status' => normalize_template_status(template['status']),
        'category' => template['category'],
        'template_id' => template['id'] || template['templateId'],
        'components' => parse_template_components(template)
      }
    end
  end

  def normalize_template_status(status)
    status_mapping = {
      'APPROVED' => 'approved',
      'PENDING' => 'pending',
      'PENDING_APPROVAL' => 'pending',
      'REJECTED' => 'rejected',
      'PAUSED' => 'paused',
      'DISABLED' => 'disabled'
    }

    status_mapping[status&.upcase] || status&.downcase || 'pending'
  end

  def parse_template_components(template)
    return [] unless template['components'].present?

    template['components'].map do |component|
      {
        'type' => component['type'],
        'text' => component['text'],
        'parameters' => component['example']&.map { |ex| { 'text' => ex } } || []
      }
    end
  end

  def process_gupshup_response(response, message)
    parsed = response.parsed_response

    if response.success? && success_response?(parsed)
      # Gupshup retorna message_id no formato específico
      message_id = parsed.dig('message', 'id') || parsed['messageId']
      message_id
    else
      handle_gupshup_error(response, message)
      nil
    end
  end

  def success_response?(parsed)
    return true if parsed['status'] == 'submitted' || parsed['status'] == 'success'
    return true if parsed['message'].present? && parsed['error'].blank?

    false
  end

  def handle_gupshup_error(response, message)
    error_msg = error_message(response)
    Rails.logger.error "[GUPSHUP] Erro ao enviar mensagem: #{error_msg}"

    return if message.blank?

    message.external_error = error_msg
    message.status = :failed
    message.save!
  end

  def error_message(response)
    parsed = response.parsed_response

    parsed&.dig('error', 'message') ||
    parsed&.dig('error', 'error_data', 'details') ||
    parsed&.dig('message') ||
    "Erro HTTP #{response.code}: #{response.message}"
  end
end
