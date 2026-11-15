const API_BASE_URL = "/sys-monitor/api";

async function apiRequest(endpoint) {
  let response;

  try {
    response = await fetch(`${API_BASE_URL}${endpoint}`);
  } catch (error) {
    throw new Error(
      `Unable to reach the monitoring backend: ${error.message}`
    );
  }

  if (!response.ok) {
    throw new Error(
      `API request failed: ${response.status} ${response.statusText}`
    );
  }

  try {
    return await response.json();
  } catch {
    throw new Error("The backend returned an invalid JSON response.");
  }
}

export function getApplications() {
  return apiRequest("/applications");
}

export function getDatabase() {
  return apiRequest("/database");
}
