const FIRST_NAMES = [
  'James', 'Mary', 'Robert', 'Patricia', 'John', 'Jennifer', 'Michael', 'Linda',
  'David', 'Elizabeth', 'William', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica',
  'Thomas', 'Sarah', 'Charles', 'Karen', 'Christopher', 'Lisa', 'Daniel', 'Nancy',
  'Matthew', 'Betty', 'Anthony', 'Sandra', 'Mark', 'Ashley', 'Donald', 'Emily',
  'Steven', 'Kimberly', 'Andrew', 'Donna', 'Paul', 'Emily', 'Joshua', 'Michelle'
];

const LAST_NAMES = [
  'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
  'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson',
  'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee', 'Perez', 'Thompson',
  'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson', 'Walker'
];

export interface Profile {
  firstName: string;
  lastName: string;
  birthDate: {
    year: number;
    month: number;
    day: number;
  };
  emailPrefix: string;
  password: string;
}

export function generateRandomProfile(domain: 'outlook.com' | 'hotmail.com' = 'outlook.com'): Profile {
  const firstName = FIRST_NAMES[Math.floor(Math.random() * FIRST_NAMES.length)];
  const lastName = LAST_NAMES[Math.floor(Math.random() * LAST_NAMES.length)];
  
  // Birth year between 1985 and 2002
  const year = Math.floor(Math.random() * 18) + 1985;
  const month = Math.floor(Math.random() * 12) + 1;
  const day = Math.floor(Math.random() * 27) + 1;

  // Generate random email prefix: e.g. james.smith.x9k2 or jsmith8492
  const randNum = Math.floor(Math.random() * 89999) + 10000;
  const randChars = Math.random().toString(36).substring(2, 6);
  const patternType = Math.floor(Math.random() * 3);
  
  let emailPrefix = '';
  if (patternType === 0) {
    emailPrefix = `${firstName.toLowerCase()}.${lastName.toLowerCase()}.${randNum}`;
  } else if (patternType === 1) {
    emailPrefix = `${firstName.charAt(0).toLowerCase()}${lastName.toLowerCase()}${randChars}`;
  } else {
    emailPrefix = `${firstName.toLowerCase()}${randNum}${lastName.charAt(0).toLowerCase()}`;
  }

  // Strong password satisfying Microsoft rules (At least 8 chars, uppercase, lowercase, numbers, symbol)
  const password = generateStrongPassword();

  return {
    firstName,
    lastName,
    birthDate: { year, month, day },
    emailPrefix,
    password
  };
}

function generateStrongPassword(): string {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const digits = '23456789';
  const special = '!@#$%^&*()_+-=';

  let pass = '';
  pass += upper[Math.floor(Math.random() * upper.length)];
  pass += lower[Math.floor(Math.random() * lower.length)];
  pass += lower[Math.floor(Math.random() * lower.length)];
  pass += digits[Math.floor(Math.random() * digits.length)];
  pass += digits[Math.floor(Math.random() * digits.length)];
  pass += special[Math.floor(Math.random() * special.length)];

  const all = upper + lower + digits + special;
  for (let i = 0; i < 6; i++) {
    pass += all[Math.floor(Math.random() * all.length)];
  }

  // Shuffle string
  return pass.split('').sort(() => 0.5 - Math.random()).join('');
}
