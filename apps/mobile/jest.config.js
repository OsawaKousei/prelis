module.exports = {
  preset: 'jest-expo',
  testMatch: ['**/?(*.)+(test).[jt]s?(x)'],
  moduleNameMapper: {
    '^react$': require.resolve('react'),
    '^react-native$': require.resolve('react-native'),
    '^@prelis/core$': '<rootDir>/../../packages/core/src/index.ts',
  },
};
