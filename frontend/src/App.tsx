import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AuthProvider } from "@/auth/AuthContext";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { RequireAuth } from "@/components/RequireAuth";
import Index from "./pages/Index";
import Marketing from "./pages/Marketing";
import Login from "./pages/Login";
import Signup from "./pages/Signup";
import VerificationPending from "./pages/VerificationPending";
import ResetPassword from "./pages/ResetPassword";
import AuthAction from "./pages/AuthAction";
import ChooseUsername from "./pages/ChooseUsername";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <AuthProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<Marketing />} />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/reset-password" element={<ResetPassword />} />
            <Route path="/verification" element={<VerificationPending />} />
            <Route path="/auth/action" element={<AuthAction />} />
            <Route path="/choose-username" element={<ChooseUsername />} />
            <Route
              path="/app"
              element={
                <RequireAuth>
                  <Index />
                </RequireAuth>
              }
            />
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </AuthProvider>
  </QueryClientProvider>
);

export default App;
