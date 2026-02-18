# Serviço para processamento de mensagens recebidas via Gupshup
# O formato de webhook do Gupshup difere do Meta Cloud API
#
# Estrutura típica do payload do Gupshup:
# {
#   "app": "nome_do_app",
#   "timestamp": 1234567890,
#   "version": 2,
#   "type": "message",
#   "payload": {
#     "id": "message_id",
#     "type": "text|image|video|audio|document|location|contacts",
#     "sender": { "phone": "5511999999999", "name": "Nome" },
#     "context": { "id": "message_id_respondido" },
#     "text": "Conteúdo da mensagem",
#     ...
#   }
# }
#
class Whatsapp::IncomingMessageGupshupService < Whatsapp::IncomingMessageBaseService
  private

  def processed_params
    @processed_params ||= normalize_gupshup_payload
  end

  # Normaliza o formato do Gupshup para o formato esperado pelo serviço base
  def normalize_gupshup_payload
    return params if params[:entry].present? # Já está no formato Cloud API

    # Extrai dados do payload do Gupshup
    payload = params[:payload] || params

    # Normaliza para formato similar ao Cloud API para reutilizar a lógica base
    {
      contacts: extract_contacts(payload),
      messages: extract_messages(payload),
      statuses: extract_statuses(params)
    }.compact
  end

  def extract_contacts(payload)
    return nil unless payload[:sender].present?

    [{
      wa_id: format_phone_number(payload[:sender][:phone]),
      profile: {
        name: payload[:sender][:name] || payload[:sender][:phone]
      }
    }]
  end

  def extract_messages(payload)
    return nil unless payload[:id].present? && params[:type] != 'message-event'

    message_type = payload[:type] || 'text'
    from = format_phone_number(payload[:sender]&.dig(:phone))

    message = {
      id: payload[:id],
      type: message_type,
      from: from,
      timestamp: payload[:timestamp] || params[:timestamp]
    }

    # Adiciona contexto de resposta (reply)
    if payload[:context]&.dig(:id).present?
      message[:context] = { id: payload[:context][:id] }
    end

    # Adiciona conteúdo específico do tipo
    add_message_content(message, message_type, payload)

    [message]
  end

  def add_message_content(message, type, payload)
    case type
    when 'text'
      message[:text] = { body: payload[:text] || payload.dig(:payload, :text) }
    when 'image'
      message[:image] = build_media_payload(payload, 'image')
    when 'video'
      message[:video] = build_media_payload(payload, 'video')
    when 'audio', 'voice'
      message[:audio] = build_media_payload(payload, 'audio')
      message[:type] = 'audio'
    when 'document'
      message[:document] = build_document_payload(payload)
    when 'location'
      message[:location] = build_location_payload(payload)
    when 'contacts'
      message[:contacts] = payload[:contacts] || [payload[:contact]]
    when 'button'
      message[:button] = { text: payload.dig(:button, :text) || payload[:text] }
    when 'interactive'
      message[:interactive] = payload[:interactive]
    end
  end

  def build_media_payload(payload, type)
    media_data = payload[type.to_sym] || payload[:payload] || {}

    {
      id: media_data[:id] || media_data[:media_id],
      caption: media_data[:caption] || payload[:text],
      mime_type: media_data[:mime_type] || media_data[:contentType]
    }.compact
  end

  def build_document_payload(payload)
    doc_data = payload[:document] || payload[:payload] || {}

    {
      id: doc_data[:id] || doc_data[:media_id],
      caption: doc_data[:caption] || payload[:text],
      filename: doc_data[:filename] || doc_data[:name],
      mime_type: doc_data[:mime_type] || doc_data[:contentType]
    }.compact
  end

  def build_location_payload(payload)
    location = payload[:location] || payload[:payload] || {}

    {
      latitude: location[:latitude],
      longitude: location[:longitude],
      name: location[:name],
      address: location[:address],
      url: location[:url]
    }.compact
  end

  def extract_statuses(params)
    return nil unless params[:type] == 'message-event' || params[:type] == 'message-status'

    payload = params[:payload] || params

    [{
      id: payload[:gsId] || payload[:id] || payload.dig(:message, :id),
      status: normalize_status(payload[:status] || payload.dig(:message, :status)),
      timestamp: payload[:timestamp] || params[:timestamp],
      errors: extract_errors(payload)
    }.compact]
  end

  def normalize_status(status)
    status_mapping = {
      'enqueued' => 'sent',
      'sent' => 'sent',
      'delivered' => 'delivered',
      'read' => 'read',
      'failed' => 'failed',
      'undelivered' => 'failed',
      'seen' => 'read'
    }

    status_mapping[status&.downcase] || status&.downcase || 'sent'
  end

  def extract_errors(payload)
    return nil unless payload[:error].present? || payload.dig(:message, :error).present?

    error = payload[:error] || payload.dig(:message, :error)

    [{
      code: error[:code] || error[:error_code],
      title: error[:message] || error[:title] || error[:error_data]&.dig(:details)
    }.compact]
  end

  def format_phone_number(phone)
    return nil if phone.blank?

    # Remove prefixo whatsapp: se presente
    phone = phone.to_s.gsub(/^whatsapp:/, '')

    # Adiciona + se não presente
    phone.start_with?('+') ? phone : "+#{phone}"
  end

  def download_attachment_file(attachment_payload)
    media_id = attachment_payload[:id] || attachment_payload[:media_id]

    # Primeiro, obtém a URL do media
    url_response = HTTParty.get(
      inbox.channel.media_url(media_id),
      headers: inbox.channel.api_headers
    )

    return nil unless url_response.success?

    # Gupshup pode retornar a URL diretamente ou no corpo da resposta
    media_url = url_response.parsed_response['url'] ||
                url_response.parsed_response.dig('media', 'url')

    return Down.download(media_url, headers: inbox.channel.api_headers) if media_url.present?

    # Se não tem URL, tenta baixar diretamente
    Down.download(inbox.channel.media_url(media_id), headers: inbox.channel.api_headers)
  rescue Down::Error, Down::ClientError => e
    Rails.logger.error "[GUPSHUP] Erro ao baixar anexo: #{e.message}"
    nil
  end

  # Sobrescreve para lidar com formato de contexto do Gupshup
  def process_in_reply_to(message)
    context_id = message['context']&.dig('id') || message[:context]&.dig(:id)
    @in_reply_to_external_id = context_id
  end
end
