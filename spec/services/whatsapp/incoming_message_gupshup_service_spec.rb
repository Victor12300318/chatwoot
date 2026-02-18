require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageGupshupService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) { create(:channel_whatsapp, :gupshup, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:service) { described_class.new(inbox: inbox, params: params) }

  describe '#perform' do
    context 'quando recebe uma mensagem de texto' do
      let(:params) do
        {
          app: 'test_app',
          timestamp: 1_703_000_000,
          version: 2,
          type: 'message',
          payload: {
            id: 'gupshup_msg_123',
            type: 'text',
            sender: {
              phone: '5511999999999',
              name: 'João Silva'
            },
            text: 'Olá, tudo bem?'
          }
        }
      end

      it 'cria um contato' do
        expect { service.perform }.to change(Contact, :count).by(1)
      end

      it 'cria uma conversa' do
        expect { service.perform }.to change(Conversation, :count).by(1)
      end

      it 'cria uma mensagem' do
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content).to eq('Olá, tudo bem?')
        expect(message.message_type).to eq('incoming')
      end
    end

    context 'quando recebe uma mensagem de mídia' do
      let(:params) do
        {
          app: 'test_app',
          timestamp: 1_703_000_000,
          version: 2,
          type: 'message',
          payload: {
            id: 'gupshup_msg_456',
            type: 'image',
            sender: {
              phone: '5511999999999',
              name: 'Maria Santos'
            },
            image: {
              id: 'media_123',
              caption: 'Veja esta imagem'
            }
          }
        }
      end

      before do
        # Mock para download de mídia
        stub_request(:get, %r{api.gupshup.io/sm/api/v1/media/media_123})
          .to_return(status: 200, body: { url: 'https://example.com/image.jpg' }.to_json)

        stub_request(:get, 'https://example.com/image.jpg')
          .to_return(status: 200, body: 'fake_image_data', headers: { 'Content-Type' => 'image/jpeg' })
      end

      it 'cria uma mensagem com anexo' do
        service.perform

        message = Message.last
        expect(message.content).to eq('Veja esta imagem')
      end
    end

    context 'quando recebe uma atualização de status' do
      let(:params) do
        {
          app: 'test_app',
          timestamp: 1_703_000_000,
          version: 2,
          type: 'message-event',
          payload: {
            gsId: 'gupshup_msg_789',
            status: 'delivered',
            timestamp: 1_703_000_100
          }
        }
      end

      let!(:existing_message) do
        create(:message, source_id: 'gupshup_msg_789', inbox: inbox, account: account)
      end

      it 'atualiza o status da mensagem' do
        service.perform

        existing_message.reload
        expect(existing_message.status).to eq('delivered')
      end
    end

    context 'quando recebe uma localização' do
      let(:params) do
        {
          app: 'test_app',
          timestamp: 1_703_000_000,
          version: 2,
          type: 'message',
          payload: {
            id: 'gupshup_msg_loc',
            type: 'location',
            sender: {
              phone: '5511999999999',
              name: 'Pedro'
            },
            location: {
              latitude: -23.5505,
              longitude: -46.6333,
              name: 'São Paulo',
              address: 'São Paulo, SP, Brasil'
            }
          }
        }
      end

      it 'cria uma mensagem com anexo de localização' do
        service.perform

        message = Message.last
        expect(message.attachments.count).to eq(1)
        expect(message.attachments.first.file_type).to eq('location')
        expect(message.attachments.first.coordinates_lat).to eq(-23.5505)
        expect(message.attachments.first.coordinates_long).to eq(-46.6333)
      end
    end
  end
end
