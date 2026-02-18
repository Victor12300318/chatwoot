<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const router = useRouter();

// Campos do formulário
const inboxName = ref('');
const phoneNumber = ref('');
const apiKey = ref('');
const appName = ref('');

// Estado da UI
const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

// Validações
const rules = {
  inboxName: { required },
  phoneNumber: { required, isPhoneE164OrEmpty },
  apiKey: { required },
  appName: { required },
};

const v$ = useVuelidate(rules, { inboxName, phoneNumber, apiKey, appName });

// Cria o canal WhatsApp via Gupshup
const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value?.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'gupshup',
        provider_config: {
          api_key: apiKey.value,
          app_name: appName.value,
        },
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: whatsappChannel.id,
      },
    });
  } catch (error) {
    useAlert(
      error.message ||
        'Não foi possível criar o canal WhatsApp via Gupshup. Verifique suas credenciais.'
    );
  }
};
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
    <!-- Nome da Caixa de Entrada -->
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <!-- Número de Telefone -->
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <!-- Nome do App (Específico do Gupshup) -->
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.appName.$error }">
        <span>{{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.APP_NAME.LABEL') }}</span>
        <input
          v-model="appName"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.APP_NAME.PLACEHOLDER')
          "
          @blur="v$.appName.$touch"
        />
        <span v-if="v$.appName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.APP_NAME.ERROR') }}
        </span>
      </label>
      <p class="text-xs text-n-slate-10 mt-1">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.APP_NAME.HELP') }}
      </p>
    </div>

    <!-- Chave de API -->
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.apiKey.$error }">
        <span>{{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}</span>
        <input
          v-model="apiKey"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER')"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
        </span>
      </label>
      <p class="text-xs text-n-slate-10 mt-1">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.API_KEY.HELP') }}
      </p>
    </div>

    <!-- URL de Callback -->
    <div class="flex-shrink-0 flex-grow-0 mt-4">
      <div
        class="bg-n-slate-2 dark:bg-n-slate-900 p-4 rounded-lg border border-n-weak"
      >
        <h4 class="text-sm font-medium text-n-slate-12 mb-2">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.CALLBACK_TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-11 mb-3">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.CALLBACK_SUBTITLE') }}
        </p>
        <div
          class="bg-n-slate-3 dark:bg-n-slate-800 p-2 rounded font-mono text-xs text-n-slate-12 break-all"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GUPSHUP.CALLBACK_URL_PLACEHOLDER') }}
        </div>
      </div>
    </div>

    <!-- Botão de Envio -->
    <div class="w-full mt-6">
      <NextButton
        type="submit"
        solid
        blue
        :is-loading="uiFlags.isCreating"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
      />
    </div>
  </form>
</template>
