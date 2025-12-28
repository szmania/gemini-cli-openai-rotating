import { Env, OAuth2Credentials } from "./types";
import { hashString } from "./utils/hashing";
import {
	CODE_ASSIST_ENDPOINT,
	CODE_ASSIST_API_VERSION,
	KV_CREDS_INDEX,
	OAUTH_CLIENT_ID,
	OAUTH_CLIENT_SECRET,
	OAUTH_REFRESH_URL,
	TOKEN_BUFFER_TIME,
	KV_TOKEN_KEY
} from "./config";

// Auth-related interfaces
interface TokenRefreshResponse {
	access_token: string;
	expires_in: number;
}

interface CachedTokenData {
	access_token: string;
	expiry_date: number;
	cached_at: number;
}

interface TokenCacheInfo {
	cached: boolean;
	cached_at?: string;
	expires_at?: string;
	time_until_expiry_seconds?: number;
	is_expired?: boolean;
	message?: string;
	error?: string;
}

/**
 * Handles OAuth2 authentication and Google Code Assist API communication.
 * Manages token caching, refresh, and API calls.
 */
export class AuthManager {
	private env: Env;
	private accessToken: string | null = null;
	public credsIndex: number = 0;
	private credsHash: number = 0;
	private credentials: string[] = [];

	constructor(env: Env) {
		this.env = env;
		// Load credentials from environment variables on construction
		this.credentials = Array.from({ length: 100 })
			.map((_, i) => {
				return (this.env[("GCP_SERVICE_ACCOUNT_" + i) as keyof Env] ?? "") as string;
			})
			.filter((s) => s.length > 0);
	}

	/**
	 * Initializes authentication using OAuth2 credentials with KV storage caching.
	 */
	public async initializeAuth(): Promise<void> {
		if (this.credentials.length == 0)
			throw new Error("`GCP_SERVICE_ACCOUNT_*` environment variable not set. Please provide OAuth2 credentials JSON.");

		// Parse original credentials from environment.
		const oauth2Creds: OAuth2Credentials = JSON.parse(this.credentials[this.credsIndex]);
		this.credsHash = hashString(oauth2Creds.id_token);

		try {
			// First, try to get a cached token from KV storage
			let cachedTokenData = null;

			try {
				const cachedToken = await this.env.GEMINI_CLI_KV.get(`${KV_TOKEN_KEY}_${this.credsHash}`, "json");
				if (cachedToken) {
					cachedTokenData = cachedToken as CachedTokenData;
					console.log("Found cached token in KV storage");
				}
			} catch (kvError) {
				console.log("No cached token found in KV storage or KV error:", kvError);
			}

			// Check if cached token is still valid (with buffer)
			if (cachedTokenData) {
				const timeUntilExpiry = cachedTokenData.expiry_date - Date.now();
				if (timeUntilExpiry > TOKEN_BUFFER_TIME) {
					this.accessToken = cachedTokenData.access_token;
					console.log(`Using cached token, valid for ${Math.floor(timeUntilExpiry / 1000)} more seconds`);
					return;
				}
				console.log("Cached token expired or expiring soon");
			}

			// Check if the original token is still valid
			const timeUntilExpiry = oauth2Creds.expiry_date - Date.now();
			if (timeUntilExpiry > TOKEN_BUFFER_TIME) {
				// Original token is still valid, cache it and use it
				this.accessToken = oauth2Creds.access_token;
				console.log(`Original token is valid for ${Math.floor(timeUntilExpiry / 1000)} more seconds`);

				// Cache the token in KV storage
				await this.cacheTokenInKV(oauth2Creds.access_token, oauth2Creds.expiry_date);
				return;
			}

			// Both original and cached tokens are expired, refresh the token
			console.log("All tokens expired, refreshing...");
			await this.refreshAndCacheToken(oauth2Creds.refresh_token);
		} catch (e: unknown) {
			const errorMessage = e instanceof Error ? e.message : String(e);
			console.error("Failed to initialize authentication:", e);
			throw new Error("Authentication failed: " + errorMessage);
		}
	}

	public async rotateCredentials() {
		this.credsIndex = Math.min(
			parseInt((await this.env.GEMINI_CLI_KV.get(KV_CREDS_INDEX, "text").catch(() => "0")) ?? "0"),
			this.credentials.length - 1
		);

		console.log(this.credsIndex);

		let nextCredsIndex = this.credsIndex + 1;
		if (nextCredsIndex > this.credentials.length - 1) nextCredsIndex = 0;
		console.log("Rotated credentials to", nextCredsIndex);
		await this.env.GEMINI_CLI_KV.put(KV_CREDS_INDEX, nextCredsIndex.toString());
	}

	/**
	 * Refresh the OAuth token and cache it in KV storage.
	 */
	private async refreshAndCacheToken(refreshToken: string): Promise<void> {
		console.log("Refreshing OAuth token...");

		const refreshResponse = await fetch(OAUTH_REFRESH_URL, {
			method: "POST",
			headers: {
				"Content-Type": "application/x-www-form-urlencoded"
			},
			body: new URLSearchParams({
				client_id: OAUTH_CLIENT_ID,
				client_secret: OAUTH_CLIENT_SECRET,
				refresh_token: refreshToken,
				grant_type: "refresh_token"
			})
		});

		if (!refreshResponse.ok) {
			const errorText = await refreshResponse.text();
			console.error("Token refresh failed:", errorText);
			throw new Error(`Token refresh failed: ${errorText}`);
		}

		const refreshData = (await refreshResponse.json()) as TokenRefreshResponse;
		this.accessToken = refreshData.access_token;

		// Calculate expiry time (typically 1 hour from now)
		const expiryTime = Date.now() + refreshData.expires_in * 1000;

		console.log("Token refreshed successfully");
		console.log(`New token expires in ${refreshData.expires_in} seconds`);

		// Cache the new token in KV storage
		await this.cacheTokenInKV(refreshData.access_token, expiryTime);
	}

	/**
	 * Cache the access token in KV storage.
	 */
	private async cacheTokenInKV(accessToken: string, expiryDate: number): Promise<void> {
		try {
			const tokenData = {
				access_token: accessToken,
				expiry_date: expiryDate,
				cached_at: Date.now()
			};

			// Cache for slightly less than the token expiry to be safe
			const ttlSeconds = Math.floor((expiryDate - Date.now()) / 1000) - 300; // 5 minutes buffer

			if (ttlSeconds > 0) {
				await this.env.GEMINI_CLI_KV.put(`${KV_TOKEN_KEY}_${this.credsHash}`, JSON.stringify(tokenData), {
					expirationTtl: ttlSeconds
				});
				console.log(`Token cached in KV storage with TTL of ${ttlSeconds} seconds`);
			} else {
				console.log("Token expires too soon, not caching in KV");
			}
		} catch (kvError) {
			console.error("Failed to cache token in KV storage:", kvError);
			// Don't throw an error here as the token is still valid, just not cached
		}
	}

	/**
	 * Clear cached token from KV storage.
	 */
	public async clearTokenCache(): Promise<void> {
		try {
			await this.env.GEMINI_CLI_KV.delete(`${KV_TOKEN_KEY}_${this.credsHash}`);
			console.log("Cleared cached token from KV storage");
		} catch (kvError) {
			console.log("Error clearing KV cache:", kvError);
		}
	}

	/**
	 * Get cached token info from KV storage.
	 */
	public async getCachedTokenInfo(): Promise<TokenCacheInfo> {
		try {
			const cachedToken = await this.env.GEMINI_CLI_KV.get(`${KV_TOKEN_KEY}_${this.credsHash}`, "json");
			if (cachedToken) {
				const tokenData = cachedToken as CachedTokenData;
				const timeUntilExpiry = tokenData.expiry_date - Date.now();

				return {
					cached: true,
					cached_at: new Date(tokenData.cached_at).toISOString(),
					expires_at: new Date(tokenData.expiry_date).toISOString(),
					time_until_expiry_seconds: Math.floor(timeUntilExpiry / 1000),
					is_expired: timeUntilExpiry < 0
					// Removed token_preview for security
				};
			}
			return { cached: false, message: "No token found in cache" };
		} catch (e: unknown) {
			const errorMessage = e instanceof Error ? e.message : String(e);
			return { cached: false, error: errorMessage };
		}
	}

	/**
	 * A generic method to call a Code Assist API endpoint.
	 */
	public async callEndpoint(method: string, body: Record<string, unknown>, isRetry: boolean = false): Promise<unknown> {
		await this.initializeAuth();

		const response = await fetch(`${CODE_ASSIST_ENDPOINT}/${CODE_ASSIST_API_VERSION}:${method}`, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
				Authorization: `Bearer ${this.accessToken}`
			},
			body: JSON.stringify(body)
		});

		if (!response.ok) {
			if (response.status === 401 && !isRetry) {
				console.log("Got 401 error, clearing token cache and retrying...");
				this.accessToken = null; // Clear cached token
				await this.clearTokenCache(); // Clear KV cache
				await this.initializeAuth(); // This will refresh the token
				return this.callEndpoint(method, body, true); // Retry once
			}
			const errorText = await response.text();
			throw new Error(`API call failed with status ${response.status}: ${errorText}`);
		}

		return response.json();
	}

	/**
	 * Get the current access token.
	 */
	public getAccessToken(): string | null {
		return this.accessToken;
	}

	/**
	 * Forces rotation to the next available credential and re-initializes authentication.
	 * This is used for retrying requests with a different account when one is rate-limited.
	 * @param failedProjectId Optional project ID that failed, for enhanced logging
	 * @returns Promise<boolean> indicating if rotation was successful
	 */
	public async forceNextCredential(failedProjectId?: string): Promise<boolean> {
		// If we only have one credential or none, we can't rotate
		if (this.credentials.length <= 1) {
			console.log("Cannot rotate credentials: only one or no credentials available");
			return false;
		}

		// Store current index for logging
		const oldCredsIndex = this.credsIndex;
		
		// Calculate the next credential index
		const nextCredsIndex = (this.credsIndex + 1) % this.credentials.length;
		
		// Update current index
		this.credsIndex = nextCredsIndex;
		
		// Update KV store to point to the following credential for the next request
		const followingIndex = (nextCredsIndex + 1) % this.credentials.length;
		await this.env.GEMINI_CLI_KV.put(KV_CREDS_INDEX, followingIndex.toString());
		
		// Reset access token and re-initialize auth with new credential
		this.accessToken = null;
		await this.initializeAuth();
		
		// Enhanced logging with project ID if provided
		if (failedProjectId) {
			console.log(`Rotated from credential index ${oldCredsIndex} (project: ${failedProjectId}) to index ${nextCredsIndex}`);
		} else {
			console.log(`Successfully rotated to credential index ${nextCredsIndex}`);
		}
		return true;
	}
}
