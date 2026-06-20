import { useState } from 'react';
import Layout from './components/Layout';
import Overview from './pages/Overview';
import Treasury from './pages/Treasury';
import ManagerDashboard from './pages/ManagerDashboard';
import RecipientPortal from './pages/RecipientPortal';
import ReviewerInbox from './pages/ReviewerInbox';
import PublicView from './pages/PublicView';

export default function App() {
  const [tab, setTab] = useState('overview');

  return (
    <Layout activeTab={tab} onTabChange={setTab}>
      {tab === 'overview'   && <Overview onTabChange={setTab} />}
      {tab === 'treasury'   && <Treasury />}
      {tab === 'manager'    && <ManagerDashboard />}
      {tab === 'recipient'  && <RecipientPortal />}
      {tab === 'reviewer'   && <ReviewerInbox />}
      {tab === 'public'     && <PublicView />}
    </Layout>
  );
}
