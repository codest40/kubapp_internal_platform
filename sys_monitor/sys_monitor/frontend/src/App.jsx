import { useCallback, useEffect, useState } from "react";
import { getApplications, getDatabase } from "./services/api";
import "./App.css";

const navigation = [
  { id: "overview", label: "Overview", icon: "◫" },
  { id: "applications", label: "Applications", icon: "▤" },
  { id: "databases", label: "Databases", icon: "▥" },
];

function formatDate(value) {
  if (!value) return "Not available";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Not available";
  }

  return date.toLocaleString();
}

function StatusBadge({ status }) {
  const normalized = String(status || "unknown").toLowerCase();

  const label =
    normalized.charAt(0).toUpperCase() + normalized.slice(1);

  return (
    <span className={`status-badge status-${normalized}`}>
      <span className="status-dot" />
      {label}
    </span>
  );
}

function Sidebar({ activePage, onNavigate, applicationCount }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brand-mark">K</div>

        <div className="brand-copy">
          <span className="brand-name">sys_monitor</span>
          <span className="brand-caption">SYSTEM OBSERVABILITY</span>
        </div>
      </div>

      <div className="workspace-label">WORKSPACE</div>

      <div className="workspace-card">
        <div className="workspace-avatar">K</div>

        <div className="workspace-copy">
          <strong>KUBAPP</strong>
          <span>Development environment</span>
        </div>

        <span className="workspace-indicator" />
      </div>

      <div className="navigation-label">MONITORING</div>

      <nav className="navigation">
        {navigation.map((item) => (
          <button
            key={item.id}
            className={`nav-item ${
              activePage === item.id ? "nav-item-active" : ""
            }`}
            onClick={() => onNavigate(item.id)}
          >
            <span className="nav-icon">{item.icon}</span>
            <span>{item.label}</span>

            {item.id === "applications" && (
              <span className="nav-count">{applicationCount}</span>
            )}
          </button>
        ))}
      </nav>

      <div className="sidebar-bottom">
        <div className="sidebar-status">
          <span className="status-dot status-dot-muted" />

          <div>
            <strong>Monitoring service</strong>
            <span>API integration enabled</span>
          </div>
        </div>

        <div className="sidebar-footer">
          <span className="footer-mark">K</span>
          <span>KUBAPP Platform</span>
          <span className="version">v0.1.0</span>
        </div>
      </div>
    </aside>
  );
}

function PageHeading({ eyebrow, title, description }) {
  return (
    <div className="page-heading">
      <div>
        <div className="eyebrow">{eyebrow}</div>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>

      <div className="environment-pill">
        <span className="environment-dot" />
        DEVELOPMENT
      </div>
    </div>
  );
}

function MetricCard({ label, value, detail, icon, accent }) {
  return (
    <article className="metric-card">
      <div className="metric-top">
        <span className="metric-label">{label}</span>
        <span className={`metric-icon metric-icon-${accent}`}>
          {icon}
        </span>
      </div>

      <div className="metric-value">{value}</div>
      <div className="metric-detail">{detail}</div>
    </article>
  );
}

function SectionHeader({ title, description, action }) {
  return (
    <div className="section-header">
      <div>
        <h2>{title}</h2>
        <p>{description}</p>
      </div>

      {action}
    </div>
  );
}

function ApplicationTable({ items, environment }) {
  if (items.length === 0) {
    return (
      <p className="empty-state">
        No applications returned by the API.
      </p>
    );
  }

  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>APPLICATION</th>
            <th>ENVIRONMENT</th>
            <th>STATUS</th>
            <th>READINESS</th>
            <th>LIVENESS</th>
          </tr>
        </thead>

        <tbody>
          {items.map((app) => (
            <tr key={app.name}>
              <td>
                <div className="resource-name">
                  <div className="resource-icon application-icon">
                    A
                  </div>

                  <div>
                    <strong>{app.name}</strong>
                    <span>
                      {app.url || "Endpoint not available"}
                    </span>
                  </div>
                </div>
              </td>

              <td>
                <span className="environment-tag">
                  {environment || "—"}
                </span>
              </td>

              <td>
                <StatusBadge status={app.status} />
              </td>

              <td>
                <StatusBadge status={app.readiness?.status} />
              </td>

              <td>
                <StatusBadge status={app.liveness?.status} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function DatabaseTable({ items }) {
  if (items.length === 0) {
    return (
      <p className="empty-state">
        No database records returned by the API.
      </p>
    );
  }

  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>DATABASE</th>
            <th>ENGINE</th>
            <th>PROVIDER</th>
            <th>CONNECTION</th>
            <th>CHECK DURATION</th>
          </tr>
        </thead>

        <tbody>
          {items.map((database) => {
            const check = database.checks?.[0];
            const duration = check?.duration_ms;

            return (
              <tr key={database.id || database.name}>
                <td>
                  <div className="resource-name">
                    <div className="resource-icon database-icon">
                      D
                    </div>

                    <div>
                      <strong>{database.name}</strong>
                      <span>
                        {check?.message ||
                          "No connection details available"}
                      </span>
                    </div>
                  </div>
                </td>

                <td>{database.engine || "—"}</td>
                <td>{database.provider || "—"}</td>

                <td>
                  <StatusBadge status={database.status} />
                </td>

                <td>
                  <span className="latency-value">
                    {typeof duration === "number"
                      ? `${Math.round(duration)} ms`
                      : "—"}
                  </span>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="information-note">
      <span className="note-icon">i</span>
      <p>Loading monitoring data from the backend...</p>
    </div>
  );
}

function ErrorMessage({ message }) {
  if (!message) return null;

  return (
    <div className="api-error" role="alert">
      <strong>Unable to load monitoring data</strong>
      <p>{message}</p>
    </div>
  );
}

function Overview({
  applications,
  environment,
  database,
  applicationSummary,
  databaseError,
  applicationsError,
  loading,
  onNavigate,
}) {
  const databaseItems = database ? [database] : [];

  return (
    <>
      <PageHeading
        eyebrow="MONITORING / OVERVIEW"
        title="System overview"
        description="A unified view of your applications and infrastructure dependencies."
      />

      <div className="metrics-grid">
        <MetricCard
          label="Applications"
          value={applicationSummary?.total ?? "—"}
          detail="Applications returned by the backend"
          icon="▤"
          accent="blue"
        />

        <MetricCard
          label="Healthy applications"
          value={applicationSummary?.healthy ?? "—"}
          detail="Passing application health checks"
          icon="✓"
          accent="green"
        />

        <MetricCard
          label="Databases"
          value={database ? 1 : "—"}
          detail="Database monitoring targets returned"
          icon="▥"
          accent="purple"
        />

        <MetricCard
          label="Unhealthy applications"
          value={applicationSummary?.unhealthy ?? "—"}
          detail="Applications reporting unhealthy status"
          icon="!"
          accent="orange"
        />
      </div>

      {loading && <LoadingState />}

      <ErrorMessage message={applicationsError} />
      <ErrorMessage message={databaseError} />

      <section className="content-section">
        <SectionHeader
          title="Applications"
          description="Registered workloads and their health-check status."
          action={
            <button
              className="text-button"
              onClick={() => onNavigate("applications")}
            >
              View applications <span>→</span>
            </button>
          }
        />

        {!applicationsError && (
          <ApplicationTable
            items={applications}
            environment={environment}
          />
        )}
      </section>

      <section className="content-section">
        <SectionHeader
          title="Database connections"
          description="Connectivity and database health information."
          action={
            <button
              className="text-button"
              onClick={() => onNavigate("databases")}
            >
              View databases <span>→</span>
            </button>
          }
        />

        {!databaseError && (
          <DatabaseTable items={databaseItems} />
        )}
      </section>
    </>
  );
}

function ApplicationsPage({
  applications,
  environment,
  summary,
  loading,
  error,
}) {
  return (
    <>
      <PageHeading
        eyebrow="MONITORING / APPLICATIONS"
        title="Applications"
        description="Inspect application availability, readiness, and liveness."
      />

      <div className="metrics-grid metrics-grid-small">
        <MetricCard
          label="Registered"
          value={summary?.total ?? "—"}
          detail="Applications returned by the API"
          icon="▤"
          accent="blue"
        />

        <MetricCard
          label="Healthy"
          value={summary?.healthy ?? "—"}
          detail="Passing application health checks"
          icon="✓"
          accent="green"
        />

        <MetricCard
          label="Unhealthy"
          value={summary?.unhealthy ?? "—"}
          detail="Failing application health checks"
          icon="!"
          accent="orange"
        />
      </div>

      {loading && <LoadingState />}
      <ErrorMessage message={error} />

      {!loading && !error && (
        <section className="content-section">
          <SectionHeader
            title="Application inventory"
            description="Application health and probe results."
            action={
              <span className="record-count">
                {summary?.total ?? applications.length} registered
              </span>
            }
          />

          <ApplicationTable
            items={applications}
            environment={environment}
          />
        </section>
      )}
    </>
  );
}

function DatabasesPage({ database, loading, error }) {
  const items = database ? [database] : [];

  const durationValues = (database?.checks || [])
    .map((check) => check.duration_ms)
    .filter((value) => typeof value === "number");

  const averageDuration =
    durationValues.length > 0
      ? Math.round(
          durationValues.reduce((sum, value) => sum + value, 0) /
            durationValues.length
        )
      : null;

  const connected = database?.status === "healthy" ? 1 : 0;

  return (
    <>
      <PageHeading
        eyebrow="MONITORING / DATABASES"
        title="Databases"
        description="Monitor database connectivity and connection-check duration."
      />

      <div className="metrics-grid metrics-grid-small">
        <MetricCard
          label="Registered databases"
          value={database ? 1 : "—"}
          detail="Database targets returned by the API"
          icon="▥"
          accent="purple"
        />

        <MetricCard
          label="Connected"
          value={database ? connected : "—"}
          detail="Databases reporting healthy status"
          icon="✓"
          accent="green"
        />

        <MetricCard
          label="Average check duration"
          value={
            averageDuration == null ? "—" : `${averageDuration} ms`
          }
          detail="Duration of reported database checks"
          icon="◷"
          accent="blue"
        />
      </div>

      {loading && <LoadingState />}
      <ErrorMessage message={error} />

      {!loading && !error && (
        <section className="content-section">
          <SectionHeader
            title="Database inventory"
            description="Connection health and database metadata."
            action={
              <span className="record-count">
                {items.length} returned
              </span>
            }
          />

          <DatabaseTable items={items} />
        </section>
      )}
    </>
  );
}

function App() {
  const [activePage, setActivePage] = useState("overview");

  const [applications, setApplications] = useState([]);
  const [applicationSummary, setApplicationSummary] = useState(null);
  const [environment, setEnvironment] = useState("");
  const [database, setDatabase] = useState(null);

  const [applicationsError, setApplicationsError] = useState("");
  const [databaseError, setDatabaseError] = useState("");

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState(null);

  const loadData = useCallback(async (manualRefresh = false) => {
    if (manualRefresh) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }

    const [applicationsResult, databaseResult] =
      await Promise.allSettled([
        getApplications(),
        getDatabase(),
      ]);

    if (applicationsResult.status === "fulfilled") {
      const result = applicationsResult.value;

      setEnvironment(result.environment || "");

      setApplications(
        Array.isArray(result.applications)
          ? result.applications
          : []
      );

      setApplicationSummary({
        total: result.total ?? result.applications?.length ?? 0,
        healthy: result.healthy ?? 0,
        unhealthy: result.unhealthy ?? 0,
        unknown: result.unknown ?? 0,
      });

      setApplicationsError("");
    } else {
      setApplicationsError(
        applicationsResult.reason?.message ||
          "An unexpected error occurred while loading applications."
      );
    }

    if (databaseResult.status === "fulfilled") {
      setDatabase(databaseResult.value);
      setDatabaseError("");
    } else {
      setDatabaseError(
        databaseResult.reason?.message ||
          "An unexpected error occurred while loading database status."
      );
    }

    if (
      applicationsResult.status === "fulfilled" ||
      databaseResult.status === "fulfilled"
    ) {
      setLastUpdated(new Date());
    }

    setLoading(false);
    setRefreshing(false);
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  function renderPage() {
    switch (activePage) {
      case "applications":
        return (
          <ApplicationsPage
            applications={applications}
            environment={environment}
            summary={applicationSummary}
            loading={loading}
            error={applicationsError}
          />
        );

      case "databases":
        return (
          <DatabasesPage
            database={database}
            loading={loading}
            error={databaseError}
          />
        );

      default:
        return (
          <Overview
            applications={applications}
            environment={environment}
            database={database}
            applicationSummary={applicationSummary}
            applicationsError={applicationsError}
            databaseError={databaseError}
            loading={loading}
            onNavigate={setActivePage}
          />
        );
    }
  }

  return (
    <div className="app-shell">
      <Sidebar
        activePage={activePage}
        onNavigate={setActivePage}
        applicationCount={
          applicationSummary?.total ?? applications.length
        }
      />

      <main className="main-content">
        <header className="topbar">
          <div className="breadcrumb">
            <span>KUBAPP</span>
            <span className="breadcrumb-separator">/</span>
            <strong>
              {navigation.find((item) => item.id === activePage)?.label}
            </strong>
          </div>

          <div className="topbar-right">
            <span className="preview-label">
              <span className="preview-dot" />
              {refreshing ? "REFRESHING" : "LIVE API"}
            </span>

            <button
              className="text-button"
              onClick={() => loadData(true)}
              disabled={refreshing || loading}
              title="Refresh monitoring data"
            >
              {refreshing ? "Refreshing..." : "↻ Refresh"}
            </button>

            <div className="user-avatar">K</div>
          </div>
        </header>

        <div className="page-content">{renderPage()}</div>

        <footer className="main-footer">
          <span>sys_monitor · KUBAPP Platform</span>
          <span>
            Last updated:{" "}
            {lastUpdated ? formatDate(lastUpdated) : "Not yet loaded"}
          </span>
        </footer>
      </main>
    </div>
  );
}

export default App;
