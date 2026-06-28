import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const push = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ push }) }));

import { HomeSearch } from '../components/home/HomeSearch';

afterEach(() => {
  cleanup();
  push.mockClear();
});

describe('HomeSearch', () => {
  it('routes service + commune to the existing landing', () => {
    render(<HomeSearch />);
    fireEvent.change(screen.getByLabelText('Service ou salon'), {
      target: { value: 'Coiffure' },
    });
    fireEvent.change(screen.getByLabelText('Commune'), {
      target: { value: 'Cocody' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Rechercher' }));
    expect(push).toHaveBeenCalledWith('/coiffure-cocody');
  });

  it('routes free text to /recherche', () => {
    render(<HomeSearch />);
    fireEvent.change(screen.getByLabelText('Service ou salon'), {
      target: { value: 'coupe afro' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Rechercher' }));
    expect(push).toHaveBeenCalledWith('/recherche?q=coupe+afro');
  });
});
