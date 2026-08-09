import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/verification/application/member_capabilities_controller.dart';

/// Capabilities are read straight from the Community and Vault services, so
/// there is no repository to substitute. Widget tests get a client that cannot
/// reach anything: the controller treats a failed read as "no privileges",
/// which is exactly the state a test should render.
MemberCapabilitiesController testMemberCapabilitiesController() {
  final client = ApiClient(tokenStore: InMemoryTokenStore());
  return MemberCapabilitiesController(client, client);
}
