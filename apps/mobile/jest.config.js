module.exports = {
  preset: 'jest-expo',
  testMatch: ['**/?(*.)+(test).[jt]s?(x)'],
  testPathIgnorePatterns: ['/node_modules/', '/e2e/'],
  moduleNameMapper: {
    '^react$': require.resolve('react'),
    '^react-native$': require.resolve('react-native'),
    '^@prelis/core$': '<rootDir>/../../packages/core/src/index.ts',
  },
};
