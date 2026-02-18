require 'rails_helper'

RSpec.describe Whatsapp::Providers::GupshupService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, :gupshup, account: account, sync_templates: false, validate_provider_config: false) }
  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  describe '#api_headers' do
    it 'retorna os headers corretos para Gupshup' do
      headers = service.api_headers

      expect(headers['apikey']).to eq('test_gupshup_key')
      expect(headers['Content-Type']).to eq('application/json')
    end
  end

  describe '#media_url' do
    it 'retorna a URL correta para mídia' do
      expect(service.media_url('12345')).to include('/media/12345')
    end
  end

  describe '#validate_provider_config?' do
    context 'quando a configuração é válida' do
      before do
        stub_request(:get, %r{api.gupshup.io/sm/api/v1/app/test_app})
          .to_return(status: 200, body: { status: 'success' }.to_json)
      end

      it 'retorna true' do
        expect(service.validate_provider_config?).to be true
      end
    end

    context 'quando a configuração é inválida' do
      before do
        stub_request(:get, %r{api.gupshup.io/sm/api/v1/app/test_app})
          .to_return(status: 401, body: { status: 'error' }.to_json)
      end

      it 'retorna false' do
        expect(service.validate_provider_config?).to be false
      end
    end

    context 'quando api_key está ausente' do
      before do
        whatsapp_channel.provider_config['api_key'] = nil
      end

      it 'retorna false' do
        expect(service.validate_provider_config?).to be false
      end
    end

    context 'quando app_name está ausente' do
      before do
        whatsapp_channel.provider_config['app_name'] = nil
      end

      it 'retorna false' do
        expect(service.validate_provider_config?).to be false
      end
    end
  end

  describe '#send_message' do
    let(:message) { create(:message, content: 'Olá, mundo!') }
    let(:phone_number) { '+5511999999999' }

    before do
      stub_request(:post, %r{api.gupshup.io/sm/api/v1/msg})
        .to_return(status: 200, body: { status: 'submitted', messageId: 'gupshup_msg_123' }.to_json)
    end

    it 'envia mensagem de texto' do
      result = service.send_message(phone_number, message)

      expect(result).to eq('gupshup_msg_123')
    end
  end

  describe '#send_template' do
    let(:message) { create(:message) }
    let(:phone_number) { '+5511999999999' }
    let(:template_info) do
      {
        name: 'hello_template',
        template_id: 'template_123',
        lang_code: 'pt_BR',
        parameters: [{ text: 'João' }, { text: '12345' }]
      }
    end

    before do
      stub_request(:post, %r{api.gupshup.io/sm/api/v1/template/msg})
        .to_return(status: 200, body: { status: 'submitted', messageId: 'template_msg_123' }.to_json)
    end

    it 'envia mensagem de template' do
      result = service.send_template(phone_number, template_info, message)

      expect(result).to eq('template_msg_123')
    end
  end

  describe '#sync_templates' do
    let(:templates_response) do
      {
        templates: [
          {
            'elementName' => 'hello_template',
            'id' => 'template_123',
            'languageCode' => 'pt_BR',
            'status' => 'APPROVED',
            'category' => 'UTILITY',
            'components' => []
          }
        ]
      }
    end

    before do
      stub_request(:get, %r{api.gupshup.io/sm/api/v1/template/list/test_app})
        .to_return(status: 200, body: templates_response.to_json)
    end

    it 'sincroniza templates do Gupshup' do
      service.sync_templates

      whatsapp_channel.reload
      expect(whatsapp_channel.message_templates).not_to be_empty
      expect(whatsapp_channel.message_templates.first['name']).to eq('hello_template')
    end
  end
end
