from litellm.integrations.custom_logger import CustomLogger


class BackendLogger(CustomLogger):
    async def async_post_call_success_deployment_hook(self, request_data, response, call_type):
        print(f"llm_backend status=success model={request_data.get('model')} base={request_data.get('api_base')}", flush=True)

    async def async_post_call_failure_deployment_hook(self, request_data, exception, call_type, fallback_depth=None):
        print(f"llm_backend status=failure model={request_data.get('model')} base={request_data.get('api_base')} error={type(exception).__name__}", flush=True)


backend_logger = BackendLogger()
