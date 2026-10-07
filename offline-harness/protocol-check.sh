#!/bin/zsh
# Local protocol probe using current production encoders. Network is opt-in.
# Usage: zsh offline-harness/protocol-check.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap "rm -rf $BUILD_DIR" EXIT

APP="$ROOT/NeoBili"
cp "$APP/Core/Models/VideoDimension.swift" \
   "$APP/Core/Models/VideoDurationFilterSettings.swift" \
   "$APP/Core/Models/PortraitVideoStore.swift" \
   "$APP/Core/Models/VideoDimensionProviders.swift" \
   "$APP/Core/Models/VideoModels.swift" \
   "$APP/Core/Models/LiveModels.swift" \
   "$APP/Core/Models/UgcSeasonModels.swift" \
   "$APP/Core/Models/FollowModels.swift" \
   "$APP/Core/Models/DynamicModels.swift" \
   "$APP/Core/Models/SearchModels.swift" \
   "$APP/Core/Models/SpaceModels.swift" \
   "$APP/Core/Models/AccountModels.swift" \
   "$APP/Core/Models/DynamicVote.swift" \
   "$APP/Core/Models/CommentModels.swift" \
   "$APP/Core/Models/LenientDecoding.swift" \
   "$APP/Core/Models/RecommendationFilter.swift" \
   "$APP/Core/UI/AppLanguage.swift" \
   "$APP/Core/Extensions/Int+BiliFormatting.swift" \
   "$APP/Core/Networking/Transport/AppNetwork.swift" \
   "$APP/Core/Networking/Reporting/RecommendationDiagnostics.swift" \
   "$APP/Core/Networking/Transport/APIClient.swift" \
   "$APP/Core/Networking/Transport/HTTPTransport.swift" \
   "$APP/Core/Networking/Transport/AppRequestEncoding.swift" \
   "$APP/Core/Networking/Identity/AppClientIdentity.swift" \
   "$APP/Core/Networking/Transport/AppProto.swift" \
   "$APP/Core/Networking/Transport/BiliHeaders.swift" \
   "$APP/Core/Networking/Identity/AppDeviceProtocol.swift" \
   "$APP/Core/Networking/Identity/AppDeviceMetadata.swift" \
   "$APP/Features/Home/RecommendationExposurePolicy.swift" \
   "$APP/Core/Networking/Recommendation/AppRecommendationProtocol.swift" \
   "$APP/Core/Networking/Reporting/AppBehaviorEncoder.swift" \
   "$APP/Core/Networking/Reporting/AppBehaviorReporter.swift" \
   "$APP/Core/Networking/Identity/AppBuvid.swift" \
   "$APP/Core/Networking/Identity/AppDeviceRegistration.swift" \
   "$APP/Core/Networking/Identity/AppGuestRegistration.swift" \
   "$APP/Core/Networking/Identity/AppTicketService.swift" \
   "$APP/Core/Networking/Identity/AppNetworkMetadata.swift" \
   "$APP/Core/Networking/Identity/PasswordCipher.swift" \
   "$APP/Core/Networking/Endpoints/BiliAPI.swift" \
   "$APP/Core/Networking/Endpoints/BiliAPI+Recommendation.swift" \
   "$APP/Core/Networking/Endpoints/BiliAPI+VideoActions.swift" \
   "$APP/Core/Networking/Recommendation/AppRecommendationSession.swift" \
   "$APP/Core/Networking/Recommendation/AppRecommendationPage.swift" \
   "$APP/Core/Networking/Recommendation/AppRelatedPage.swift" \
   "$APP/Core/Networking/Reporting/RecommendationClick.swift" \
   "$APP/Core/Networking/Recommendation/AppRecommendationDisplay.swift" \
   "$APP/Core/Networking/Recommendation/WebRecommendationPage.swift" \
   "$APP/Core/Networking/Identity/BiliPassport.swift" \
   "$APP/Core/Networking/Identity/SMSPassport.swift" \
   "$APP/Core/Networking/Identity/AppLoginRenewal.swift" \
   "$APP/Core/Networking/Identity/WBISigner.swift" \
   "$APP/Core/Networking/Identity/DeviceIdentity.swift" \
   "$APP/Core/Networking/Identity/KeychainStore.swift" \
   "$APP/Core/Networking/Identity/AppSigner.swift" \
   "$APP/Core/Networking/Transport/URL+Bili.swift" \
   "$APP/Core/UI/EnvironmentAction.swift" \
   "$APP/Features/Danmaku/DanmakuModels.swift" \
   "$APP/Features/Danmaku/DanmakuLoader.swift" \
   "$APP/Features/Home/HomeViewModel.swift" \
   "$HARNESS/src/ProtocolCheck.swift" \
   "$HARNESS/src/Stubs.swift" \
   "$BUILD_DIR/"

swiftc -O -D NEOBILI_REGRESSION -parse-as-library -o "$BUILD_DIR/protocol-check" "$BUILD_DIR"/*.swift
"$BUILD_DIR/protocol-check" "$@"
